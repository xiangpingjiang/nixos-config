{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

let
  # 识别通知来源:VS Code 扩展下 CLAUDE_CODE_ENTRYPOINT=claude-vscode,终端 CLI 下为 cli
  # (不能用 TERM_PROGRAM,它会从启动 VS Code 的终端继承,导致误判)
  detectApp = ''case "$CLAUDE_CODE_ENTRYPOINT" in *vscode*) app="VS Code" ;; *) app="Terminal" ;; esac'';

  # 可点击通知:点击通知本体跳转到对应窗口(VS Code 复用打开了该目录的窗口,终端激活 ghostty)
  # 用法: claude-notify-click <图标> <标题> <正文> <cwd> [notify-send 额外参数...]
  # notify-send -A 会一直阻塞到用户点击或通知关闭,而 hook 有 60s 超时,
  # 所以"发通知→等点击→跳转"整段用 setsid 脱离 hook 进程扔到后台,hook 本体立即返回。
  #
  # 外层那个 `timeout 120` 是堵泄漏的:不加它,没人点的 notify-send 就永不退出。
  # 2026-09-18 排查系统卡顿时发现积了 329 对 bash+notify-send,最老的活满整个
  # uptime(6.4 天);当时留了一个无 timeout 的进程做对照,22 分钟(etimes)仍在。
  # 它其实不吃内存——PSS 合计只有 22MB,`ps` 的 RSS 看着 1.2GB 是共享库被重复计了
  # 329 次——但进程表会一直涨,而且掩盖真正的问题(那次是 chromium 51 个标签页吃掉 8.4G)。
  #
  # **不要改用 notify-send 自己的 `-t`**:实测 Plasma 要到 expire_timeout 到点才发
  # NotificationClosed(-t 60000/90000/120000 各对应约 56/86/114s 才退),
  # 所以 `-t 120000` 等于让一条"任务完成"的通知挂足两分钟。外层 timeout 不碰
  # expire_timeout,通知按 Plasma 默认时长走,只有进程寿命被兜住。
  #
  # 量这类时长要用墙钟,别拿"轮询圈数 × sleep 间隔"当秒数:这台机器 1000+ 进程,
  # 一次 `pgrep -af` 就要 200ms,按 0.1s 记会把结果系统性缩到三分之一
  # (当时因此误以为存在"存活 ≈ 设定值 1/3"的规律,查了半天)。
  #
  # 局限:超过 120s 后发送进程已退出,从 Plasma 通知历史里点不会再跳转。
  notifyClick = pkgs.writeShellScript "claude-notify-click" ''
    exec ${pkgs.util-linux}/bin/setsid -f ${pkgs.bash}/bin/bash -c '
      icon="$1"; title="$2"; body="$3"; dir="$4"; shift 4
      action=$(${pkgs.coreutils}/bin/timeout 120 ${pkgs.libnotify}/bin/notify-send -a "Claude Code" -i "$icon" -A default=打开 "$@" "$title" "$body")
      [ "$action" = "default" ] || exit 0
      kdotool=${pkgs.kdotool}/bin/kdotool
      case "$CLAUDE_CODE_ENTRYPOINT" in
        # `code <dir>` 只能"请求"激活(xdg-activation):KWin 焦点窃取防护下,只有请求方
        # 是当前活跃应用时才放行——所以焦点还在 VS Code 里能跳,切到别的应用就被拒。
        # kdotool 走 KWin 脚本接口(可信,不受防护限制),按窗口标题里的目录名直接前置;
        # 目录没开窗口时才回退 `code <dir>` 新开,并轮询等窗口出现后再激活。
        *vscode*)
          pat="(^|- )''${dir##*/} - .*Visual Studio Code"
          win=""; [ -n "$dir" ] && win=$($kdotool search --name -- "$pat" | ${pkgs.coreutils}/bin/head -n1)
          if [ -z "$win" ]; then
            "$HOME/.nix-profile/bin/code" ''${dir:+"$dir"}
            for _ in 1 2 3 4 5; do
              ${pkgs.coreutils}/bin/sleep 0.4
              [ -n "$dir" ] && win=$($kdotool search --name -- "$pat" | ${pkgs.coreutils}/bin/head -n1)
              [ -n "$win" ] && break
            done
          fi
          [ -n "$win" ] && exec $kdotool windowactivate "$win"
          exec $kdotool search --class code windowactivate ;;
        # Wayland 下 wmctrl/xdotool 不可用,用 kdotool 按窗口类激活 ghostty
        *) exec $kdotool search --class ghostty windowactivate ;;
      esac
    ' claude-notify-click "$@" >/dev/null 2>&1
  '';

  # 后台子代理的运行标记(给 cc-sessions 面板用)。
  # 主 agent 派完后台子代理就 end_turn 了,transcript 里再没有任何痕迹,面板单看
  # stop_reason 只能判成"等你回话";而 background_tasks 只出现在 hook 输入里 ——
  # 它是唯一的权威源,所以在 Stop 里把快照落到 tmpfs,面板按 sessionId 查。
  # 每次 Stop 都整份重写 => 自愈:漏删一次,下一次 Stop 就纠正回来。
  bgMarkDir = ''"''${XDG_RUNTIME_DIR:-/tmp}/cc-sessions/bg"'';

  # sessionId 是 uuid,拼进路径前挡一道;异常值宁可不写也不越界
  sidGuard = ''
    case "$sid" in
      "" | *[!A-Za-z0-9-]*) sid="" ;;
    esac
  '';

  # Stop:先落标记,再决定要不要发完成通知 —— 两件事共用同一个 running 计数,
  # 而 stdin 只能读一次,所以必须在同一个脚本里做完。
  stopHook = pkgs.writeShellScript "claude-stop-hook" ''
    ${detectApp}
    in=$(cat)
    jq=${pkgs.jq}/bin/jq

    # 判据刻意收窄到 type=="subagent",不写 `background_tasks | length > 0`:
    # 后台 shell 可以是 dev server 这种不退出的进程,那样这个会话就再也收不到通知、
    # 面板也会永远显示运行中;子代理则必定结束、必定把会话唤醒。
    running=$(printf '%s' "$in" | $jq '[.background_tasks[]? | select(.type == "subagent" and .status == "running")] | length')
    sid=$(printf '%s' "$in" | $jq -r '.session_id // ""')
    ${sidGuard}
    dir=${bgMarkDir}
    if [ -n "$sid" ]; then
      if [ "$running" = 0 ]; then
        rm -f "$dir/$sid.json"
      else
        # 面板每秒读一次,所以先写临时文件再 mv,别让它读到半截 JSON
        mkdir -p "$dir"
        if printf '%s' "$in" | $jq -c --argjson n "$running" \
             '{session_id, prompt_id, cwd, n: $n, at: now}' > "$dir/.$sid.tmp"; then
          mv -f "$dir/.$sid.tmp" "$dir/$sid.json"
        else
          rm -f "$dir/.$sid.tmp"
        fi
      fi
    fi

    # 还有 running 的后台子代理时不通知:这一次 Stop 只是中途停顿,子代理结束会把
    # 会话重新唤醒接着干(实测一次提问因此触发了 3 次 Stop,最终那次 background_tasks 才是 [])
    [ "$running" = 0 ] || exit 0
    cwd=$(printf '%s' "$in" | $jq -r '.cwd // ""')
    ${notifyClick} dialog-ok "Claude Code task complete ($app)" "Project: $(basename "$cwd")" "$cwd"
  '';

  # SessionEnd:正常退出时清掉标记。异常退出(kill -9)走不到这里,靠面板那侧
  # "文件比进程还老就不认"兜底 —— resume 沿用同一个 sessionId,只能按时间分辨。
  sessionEndHook = pkgs.writeShellScript "claude-session-end-hook" ''
    sid=$(${pkgs.jq}/bin/jq -r '.session_id // ""')
    ${sidGuard}
    [ -n "$sid" ] || exit 0
    rm -f ${bgMarkDir}/"$sid".json
  '';

  # kubectl 黑名单守卫:命令里同时出现 kubectl 和 config_sg(生产 SG 集群)时,
  # 解析每个 kubectl 调用的子命令,不在只读白名单内的(apply/delete/exec/scale/...)
  # 返回 permissionDecision=ask 强制弹框询问;纯读取(get/describe/logs/...)不打扰。
  # 之所以用 hook 而不用 permissions.ask 规则:--kubeconfig 位置可变、"非读取"动词
  # 枚举不全,前缀匹配表达不了"读之外全问"这个语义。
  kubectlGuard = pkgs.writeShellScript "claude-kubectl-guard" ''
    set -f  # 关闭 glob,防止命令里的 * 被展开成文件名
    cmd=$(${pkgs.jq}/bin/jq -r '.tool_input.command // ""')
    case "$cmd" in *config_sg*) ;; *) exit 0 ;; esac
    case "$cmd" in *kubectl*) ;; *) exit 0 ;; esac
    # 只把处于"命令位置"的 kubectl 当调用:行首、分隔符(; | & 括号等)之后,
    # 或经赋值/sudo/env 等包装。引号、heredoc、commit message 里谈及 kubectl
    # 的文字因前面有普通单词,不再误触发(曾把 git commit -m "...kubectl..." 拦下)。
    # 误报残留:heredoc 里恰好以 kubectl 开头的行仍会弹框——守卫宁可误问不可漏放。
    state=idle skip=0 bad=""
    while IFS= read -r line; do
      cmdpos=1
      # 分隔符两侧补空格,让它们成为独立 token 参与命令位置判断
      line=$(printf '%s' "$line" | ${pkgs.gnused}/bin/sed 's/[;|&(){}]/ & /g')
      for tok in $line; do
        [ "$skip" = 1 ] && { skip=0; continue; }
        case "$state" in
          idle)
            if [ "$cmdpos" = 1 ]; then
              case "$tok" in kubectl|*/kubectl) state=verb ;; esac
            fi ;;
          verb)
            case "$tok" in
              # 这些全局 flag 带独立参数,跳过参数本身再找子命令
              --kubeconfig|--context|--namespace|-n|--cluster|--user|--server) skip=1 ;;
              -*) ;;
              *)
                state=idle
                case "$tok" in
                  # 只读子命令白名单,其余一律视为需要询问
                  get|describe|logs|top|events|explain|version|api-resources|api-versions|cluster-info|diff|wait|completion) ;;
                  # auth 底下混着写操作(reconcile 会创建/补全 RBAC),再看一层
                  auth) state=auth ;;
                  *) bad=$tok ;;
                esac ;;
            esac ;;
          auth)
            case "$tok" in
              --kubeconfig|--context|--namespace|-n|--cluster|--user|--server) skip=1 ;;
              -*) ;;
              *)
                case "$tok" in can-i|whoami) ;; *) bad="auth $tok" ;; esac
                state=idle ;;
            esac ;;
        esac
        # 更新命令位置:分隔符/控制字之后回到命令位置;
        # 变量赋值和 sudo/env 等包装命令保持当前值不变
        case "$tok" in
          ';'|'|'|'&'|'('|'{'|'}'|then|else|elif|do|if|while|until|exec|sudo|command|nohup|env|xargs|timeout) cmdpos=1 ;;
          *=*) ;;
          *) cmdpos=0 ;;
        esac
      done
    done <<<"$cmd"
    [ -z "$bad" ] && exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"kubectl 对 config_sg 集群的非读取操作: %s"}}\n' "$bad"
  '';

  # 终端 CLI 的版本。llm-agents 上游打包新版本有一两天的滞后,想立刻用新版就在这里钉,
  # 和 vscode.nix 里插件那份版本号是两回事(两个入口是两份互不相干的二进制,见 CLAUDE.md)。
  # 写成"上游追上就自动让路":一旦 llm-agents 的版本 >= 这里的值就直接用上游的包,
  # 例行 nix flake update 之后无需手工撤销这段 override。
  # override 本身很便宜:上游那个 drv 只是 install -Dm755 $src,没有编译,
  # 缓存未命中的代价仅仅是重新下载一次二进制,别为此把它改回去。
  # 升级手续:改 claudeCodeVersion,再跑这行拿新 hash:
  #   nix store prefetch-file --json --name claude \
  #     "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/<version>/linux-x64/claude"
  # 查上游当前最新版本:curl -s "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest"
  claudeCodeVersion = "2.1.310";
  claudeCodeUpstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  claudeCodePkg =
    if lib.versionAtLeast claudeCodeUpstream.version claudeCodeVersion then
      claudeCodeUpstream
    else
      # src 整个换掉而不是只改 version:上游若用 version 拼 URL,只改版本号会拿旧 hash 去校验新文件。
      # 上游 drv 带 versionCheckHook,二进制自报版本对不上会直接构建失败,不用另外验证。
      claudeCodeUpstream.overrideAttrs (_: {
        version = claudeCodeVersion;
        src = pkgs.fetchurl {
          url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${claudeCodeVersion}/linux-x64/claude";
          hash = "sha256-tzZ2QwrxL5cxanmLg3H4HWQPkKWL3LjzzlaoNbtH31Y=";
        };
      });
  # 跨窗口列出活跃的 Claude Code 会话(zellij 的 cc tab 循环跑的就是它,见 zellij/dev.kdl)。
  # 用 writeShellApplication 而不是 writeShellScriptBin:前者过 shellcheck,并且能用
  # runtimeInputs 固定 PATH —— 进程枚举和 transcript 解析都在 claude-sessions.py 里,
  # 所以只需要 python3(标准库,无第三方依赖)和 coreutils;zellij 的 command pane
  # 不经过 shell,PATH 取决于 zellij 服务端从哪里起的,不能指望调用者的环境。
  # bashOptions 显式去掉默认的 errexit:--watch 是长命循环,某一轮里个别命令返回非 0
  # (readlink 拿不到、渲染器偶发失败)应该下一轮重试,不该让整个面板退出。
  # 渲染器单独成包放进 profile 的 share/,好让 --watch 面板能走一条跨代稳定的路径:
  # 面板是个长命进程,bash 启动时就把当时那份 store 脚本读进去了,之后 home-manager
  # switch 换代它完全不知道 —— 2026-09-09 就是这么"检测又不准"的:两个面板分别停在
  # 09-04 / 09-08 的渲染器上,少了 09-08 那次 first_epoch 修复,终端会话永远显示"尚未对话"。
  # 逻辑全在渲染器里,所以让它每轮从 ~/.nix-profile 重新解析,switch 完立刻生效、不用重启 pane;
  # 驱动那半(取宽度/差分重绘/按键)改不了内存里的自己,由 maybe_reexec 每轮比对
  # profile 里的当前代,不同就原地 exec 换代(见 claude-sessions.sh)。
  ccSessionsRender = pkgs.writeTextFile {
    name = "cc-sessions-render";
    destination = "/share/cc-sessions/render.py";
    text = builtins.readFile ./claude-sessions.py;
  };
  ccSessions = pkgs.writeShellApplication {
    name = "cc-sessions";
    runtimeInputs = with pkgs; [
      python3
      coreutils
    ];
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    # 两个渲染器路径都由 Nix 注入:shell 那份是 readFile 进来的,自己没法插值 store 路径。
    # LIVE 是随代更新的 profile 路径(优先),PY 是钉死在本代的 store 路径(兜底:
    # profile 里还没有这个包,或者被直接从 store 调用)。用 `~` 而不是 `$HOME`:
    # 这里开着 nounset,HOME 万一没设就是脚本第一行 unbound variable 直接死,
    # 而波浪号展开不走参数展开,HOME 缺失时 bash 自己回落到 passwd。
    text = ''
      RENDER_PY_LIVE=~/.nix-profile/share/cc-sessions/render.py
      RENDER_PY=${ccSessionsRender}/share/cc-sessions/render.py
    ''
    + builtins.readFile ./claude-sessions.sh;
  };
  # 一条命令把两份 Claude Code(终端 CLI + VS Code 插件)升到最新、switch、重启 VS Code。
  # 改的是仓库里两个 claudeCodeVersion 和 hash,流程同 CLAUDE.md「升级 Claude Code 到最新」。
  # nix / home-manager 不放进 runtimeInputs:用调用方 PATH 里的那份(系统 nix、profile 里的 HM)。
  ccUpgrade = pkgs.writeShellApplication {
    name = "cc-upgrade";
    runtimeInputs = with pkgs; [
      curl
      jq
      gnused
      coreutils
      procps
    ];
    text = builtins.readFile ./cc-upgrade.sh;
  };
  # ---- 国内模型兜底入口(claude-ds)----
  # 官方 API 连不上时的备用通道。DeepSeek / 智谱 / Moonshot 都直接提供 Anthropic
  # 兼容端点,所以不需要 claude-code-router 这类协议转换层多绕一跳
  # (那东西只在 provider 没有原生端点、或要按难度在多家之间路由时才值得引入)。
  #
  # 切换走 `claude --settings <store json>`:这一层的优先级仅次于 managed settings,
  # 压得过 ~/.claude/settings.json,而且是叠加不是替换 —— hooks、permissions、
  # 全局 CLAUDE.md 全部照常生效,只有 env 里列出的那几个键被换掉。
  # 反过来,手动 `ANTHROPIC_BASE_URL=... claude` 在本机不生效:settings 文件的 env 块
  # 会替换掉从 shell 继承的同名变量(文档原文如此,实测也是)。下面 settings.env 里
  # 那行 ANTHROPIC_BASE_URL 因此被删掉了 —— 它填的就是默认值,留着唯一的效果是堵死
  # 手动 export 这条救急路径。
  #
  # 密钥不进这份 JSON:store 是全局可读的。wrapper 里 export ANTHROPIC_AUTH_TOKEN,
  # 而 settings 里**不写**这个键 —— 只有没被列出的变量才轮得到 shell 的值(已实测)。
  # 顺带:AUTH_TOKEN 一旦设了就压过已登录的 OAuth,不会把公司账号的 token 发给第三方。
  #
  # 四个模型别名都要映射。FABLE 那条现在没有配置会主动用到(2026-09-23 起
  # advisorModel 和 fable 子代理委派都撤了),但留着不花钱:用户手动 /model fable
  # 或将来改回委派时,漏了这条就会当场撞未知模型(DeepSeek 官方那份配置里没有 fable)。
  # 注意兜底状态下这套分工只剩形式:四个别名指向同一个模型,委派省不下钱,
  # 唯一还成立的作用是把子任务隔离在独立上下文里。
  mkFallbackClaude =
    {
      name,
      baseUrl,
      apiKeyPath,
      applyHint,
      models,
      autoCompactWindow,
    }:
    let
      settingsFile = pkgs.writeText "claude-${name}-settings.json" (
        builtins.toJSON {
          env = {
            ANTHROPIC_BASE_URL = baseUrl;
            # 文档:空值等于"未设"(用于提供商选择)。显式清掉,免得环境里恰好有
            # ANTHROPIC_API_KEY 时它抢在 AUTH_TOKEN 前面被当成鉴权源。
            ANTHROPIC_API_KEY = "";
            ANTHROPIC_DEFAULT_OPUS_MODEL = models.opus;
            ANTHROPIC_DEFAULT_SONNET_MODEL = models.sonnet;
            ANTHROPIC_DEFAULT_HAIKU_MODEL = models.haiku;
            ANTHROPIC_DEFAULT_FABLE_MODEL = models.fable;
            CLAUDE_CODE_SUBAGENT_MODEL = models.subagent;
            # 模型名不在 Claude Code 的 catalog 里时,它按 200k 假设上下文窗口并据此
            # 提前 auto-compact。模型名后缀 [1m] 声明真实窗口(纯本地解析,实测发出去的
            # model 字段已经把后缀剥掉),这一项再把 compact 阈值抬到窗口的 3/4。
            CLAUDE_CODE_AUTO_COMPACT_WINDOW = toString autoCompactWindow;
          };
        }
      );
    in
    pkgs.writeShellApplication {
      name = "claude-${name}";
      runtimeInputs = [ pkgs.coreutils ];
      bashOptions = [
        "nounset"
        "pipefail"
      ];
      # sops 解出来的明文在 tmpfs 上,重启即失、由 sops-nix.service 重建;
      # 读不到或还是占位值时直接退出,不要带着空 token 去撞 401。
      text = ''
        key=$(cat ${apiKeyPath} 2>/dev/null || true)
        if [ -z "$key" ] || [ "$key" = "REPLACE_ME" ]; then
          {
            echo "claude-${name}: 还没有可用的 API key。"
            echo "  1. ${applyHint}"
            echo "  2. sops secrets/llm-keys.enc.yaml   # 填进去"
            echo "  3. home-manager switch --flake . -b backup -v"
          } >&2
          exit 1
        fi
        export ANTHROPIC_AUTH_TOKEN="$key"
        exec ${claudeCodePkg}/bin/claude --settings ${settingsFile} "$@"
      '';
    };

  # DeepSeek:按量付费,没有起步价,适合"以防万一"这种低频用法。
  # 模型名和这套环境变量抄自官方集成文档
  # (https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code),
  # 只补了官方没写的 FABLE 别名。deepseek-flash 是当前在售型号,v4-pro 官方已宣布
  # 9-14 之后继续提供;没必要钉 pro —— 它贵一个数量级,而 Claude Code 这种高频
  # 工具调用场景瓶颈在往返次数不在单次推理深度。
  # 未支持的模型名会被服务端自动映射到 deepseek-flash,所以配错也不会 400。
  claudeDeepseek = mkFallbackClaude {
    name = "ds";
    baseUrl = "https://api.deepseek.com/anthropic";
    apiKeyPath = config.sops.secrets.deepseek_api_key.path;
    applyHint = "去 https://platform.deepseek.com 申请 API key";
    autoCompactWindow = 786432;
    models = {
      opus = "deepseek-flash[1m]";
      sonnet = "deepseek-flash[1m]";
      fable = "deepseek-flash[1m]";
      # haiku 还兼任后台任务(起标题、判断要不要 compact 之类),这些不需要 1M 窗口
      haiku = "deepseek-flash";
      subagent = "deepseek-flash";
    };
  };
in
{
  home.packages = [
    ccSessions
    ccUpgrade
    ccSessionsRender
    claudeDeepseek
  ];

  programs.claude-code = {
    enable = true;
    package = claudeCodePkg;

    # skill 不在这里声明:统一交给 agent-skills-nix 管理(见 ./agent-skills.nix)

    # 多模型分工(写入全局 ~/.claude/CLAUDE.md):
    # Claude Code 没有内置的"按难度自动换模型"路由(model-config 文档确认),
    # 所以只有一个机制:主会话跑 Opus,由主模型用 Agent 工具把机械/常规工作
    # 分流给更便宜的 haiku/sonnet 子代理,量大且要边做边判断的交给 opus 子代理
    # (只为隔离上下文,不省钱)(Agent 的 model 参数;
    # /model 只有用户能手动执行)。
    #
    # 2026-09-23 起整套配置不再涉及 Fable:advisorModel 撤掉、context 里的 fable
    # 子代理委派那条也删了。下面两条历史结论留着,免得日后又从头试一遍:
    #   - 2026-09-02 曾切成"Fable 主会话、不配 advisor",当天又切回来:Fable 主模型
    #     只接受 Fable 做 advisor,等于每一轮都跑最贵的模型还分不了层。
    #   - 子代理继承 advisorModel(文档:Subagents inherit the configured advisor),
    #     所以一旦配了 advisor,子代理也会各带一个,是双倍消耗。现在没配,不存在这个问题。
    # 改本文件前先查官方文档:https://code.claude.com/docs/(页面索引在 /docs/llms.txt)
    #
    # 后两节(回答风格 / 工具使用)是评估 caveman、context-mode 两个 token 优化项目后的留存物。
    # 实测本机近 30 天:assistant output 里 72% 的字符是工具参数和代码(这类项目一律不压),
    # 散文只占 22%;tool_result 里 MCP 只占 1.09%,大头是 Read(59%)和 Bash(37%)。
    # 两者的招牌收益(caveman 的 65%、context-mode 的 98%)都落不到本机,不值得装,
    # 但各有一条规则有真实增量,直接写进 context:零安装,也不额外占 context(本文件本来就常驻)。
    # 主会话 effortLevel 是 medium,需要 high 的整块活儿委派给它:子代理 frontmatter 的
    # effort 覆盖会话挡位(文档 sub-agents 页)。advisor 做不到这件事 —— 它只给建议、
    # 不接管任务,也没有单独的 effort 设置。xhigh/max 刻意不做成子代理:那种前沿难题
    # 通常要来回确认,不适合隔离上下文,由用户在主会话里 /model 手动切。
    agents.opus-high = ''
      ---
      name: opus-high
      description: Opus + high effort,用于复杂系统设计、疑难 debug、长文档分析这类需要深入推理的整块任务。目标和验收标准必须在 prompt 里写清。
      model: opus
      effort: high
      ---

      你接手的是一块需要深入推理的任务:复杂系统设计、疑难 debug 或长文档分析。
      你看不到委派方的对话,prompt 里写的就是全部上下文。

      - 先弄清目标和验收标准,再动手;证据和假设分开写,结论要能追溯到实际读过的文件或跑过的命令。
      - 中途发现方向不对就改方向,但在最终报告里说明改了什么、为什么。
      - 最终报告写给委派方:结论在前,关键依据(文件:行号、命令输出的关键一两行)在后,
        未验证的部分明确标出来。
    '';

    # haiku 那一档靠"主模型记得传 model 参数"落不了地:2026-10-24 用 tare 查 30 天,
    # haiku 一共 4 次请求;22 个 Explore 子代理全跑在 sonnet/opus 上(内置 Explore
    # 默认用主会话的模型)。所以把 haiku 钉进 agent 定义里,委派时选类型就行。
    #
    # 同名的用户级 Explore 会覆盖内置那个并保留自己的 model(文档 sub-agents 页
    # "Built-in subagents")。下面几项是照着内置版对齐的:内置 Explore 不加载 CLAUDE.md、
    # 不能改文件;自定义版这两条都要自己写,否则 omitClaudeMd 缺省会把整份全局
    # CLAUDE.md 塞进每个搜索子代理,disallowedTools 缺省则继承 Edit/Write。
    agents.Explore = ''
      ---
      name: Explore
      description: 只读的代码库搜索/探索代理(跑在 haiku 上)。需要在多个文件、目录或命名约定里查找代码、只要结论不要文件全文时使用。调用时说明搜索力度:quick / medium / very thorough。
      model: haiku
      disallowedTools: Agent, Edit, Write, NotebookEdit
      omitClaudeMd: true
      ---

      你是只读的搜索代理:在代码库里定位文件、符号、配置和调用关系,不修改任何东西。
      Bash 只用来跑只读命令(grep、find、sed -n、git log/show 之类),不要写文件、装包或改状态。

      - 按委派方要求的力度搜:quick 只查最可能的位置;very thorough 要覆盖多种命名和多个目录。
      - 读大文件先 grep -n 定位,再 sed -n 取相关段落,不要整文件读。
      - 报告写给委派方:先给结论,再列证据(文件路径:行号 + 关键一两行),
        没找到就明说没找到、查过哪些地方。
    '';

    agents.haiku-worker = ''
      ---
      name: haiku-worker
      description: 跑在 haiku 上的执行代理:按明确清单做批量小改动、跑命令并汇总输出、格式转换。不需要判断、步骤能在 prompt 里一次写清时使用。
      model: haiku
      ---

      你按委派方给的清单执行,不自行扩大范围,也不替委派方做设计决定。
      你看不到委派方的对话,prompt 里写的就是全部上下文。

      - 清单里有歧义或执行中遇到清单没覆盖的情况,停下来在报告里说明,不要猜。
      - 跑命令时只把关键输出(结果、报错的那一两行)写进报告,不要整段贴日志。
      - 报告列出做了什么、改了哪些文件、哪一步失败了。
    '';

    context = ''
      # 模型分工策略(把活儿分到对的模型和用量池)

      主会话运行在 Opus,没有配 advisor。唯一的分层手段是 Agent 工具(显式传 model 参数)。
      分给谁看两个问题,别混在一起:
      - **要不要边做边判断**:方案能不能在委派前写成清单。这才是"难度"。
      - **工作量多大**:要读、要写、要跑多少东西。量大不等于难。

      四档:

      - **haiku** —— 不用判断,照做即可:代码/文件搜索用 `Explore`(已钉在 haiku 上),
        批量小改动、跑命令并汇总输出、格式转换、按明确清单执行的操作用 `haiku-worker`。
      - **sonnet** —— 方案已定,只需一般的编码判断:普通编码修改、写测试、常见 bug 修复、
        资料调研与总结;**也包括量大但方案已定的整块活儿**(跨多个文件的改动、成体系的调研)。
        这类活儿 token 大头花在读和写而不是想,难的部分由主会话在委派前想清楚、写进 prompt。
      - **opus 子代理** —— 量大,而且要边做边判断,但目标和验收标准讲得清:
        方向未知、中途会改方向的排查(要读十几个文件)、需要权衡取舍的大范围调研。
        成本和主会话自己做相当,换来的是主会话上下文不被原始材料灌满。
        主会话挡位是 medium;其中**复杂系统设计、疑难 debug、长文档分析**这三类
        用 `opus-high` 这个 agent 类型(Opus + high effort),其余照常 `model: opus`。
      - **主会话自己做** —— 离不开当前对话上下文、或要和用户来回确认的:方案设计、
        复杂 debug、子代理结果的把关与收尾;以及一两步就能完成的事(委派本身也有开销)。

      规则:
      - 主会话每一轮都按 Opus 计费,能下放的就下放:搜索、批量改动、跑命令看输出
        这类活儿默认交给 haiku/sonnet,不要自己埋头做。
      - 委派时把上下文和验收标准写全,避免子代理来回试错反而更费 token。
      - 子代理跑在隔离上下文里:看不到当前对话,只拿得到 prompt 里写的东西,中途也无法
        追加信息。所以委派的前提是**目标和验收标准**能一次写清(交给 sonnet/haiku 的
        还要求步骤也写得清);连目标都要边聊边定的,主会话自己做。
      - 子代理返回的结果要过目,不放心的部分自己复核,不要盲信。
      - 上面那三类活儿如果离不开当前对话、只能主会话自己做,开工前提醒用户
        `/model` 把挡位切到 high(模型改不了自己的挡位);xhigh/max 由用户自己决定,不主动建议。

      # 回答风格

      - 不写工具调用旁白(「我来看一下…」「接下来我要…」),直接调用。
      - 不用装饰性表格和 emoji;表格只在真的是二维数据时用。
      - 不整段贴报错日志,引用最关键的那一两行;完整日志用户需要时再给。

      # 工具使用

      - 读大文件先用 `sed -n '起,止p'` 或 `grep -n` 取相关段落,确认需要全文再整文件读。
    '';

    settings = {
      # 主会话跑 Opus,**刻意不配 advisorModel**(2026-09-23 撤掉)。
      # 撤之前的配置是 advisorModel = "fable";要恢复的话先看清这几条约束:
      #   - 配对约束是"advisor 不弱于主模型",Opus 4.7+ 主模型只接受 Fable 或
      #     Opus 4.7+,所以没有"配个更便宜的 advisor 做分层"这个选项。
      #   - advisor 是实验特性,仅 Anthropic API 直连可用(第三方端点下会打一行
      #     no advisor rank 然后自动禁用),且依赖 feature-flag 拉取,
      #     设 DISABLE_TELEMETRY 会让它失效。
      #   - 触发时机完全由模型判断,没有任何设置项能强制、限频或按规则触发。
      # 文档:https://code.claude.com/docs/en/advisor 与 /docs/en/model-config
      model = "opus";
      # 主会话挡位,显式写出默认值 medium。难题在会话内用 /model 临时抬到 high;
      # 改这里只对新开的会话生效。
      effortLevel = "medium";
      language = "chinese";
      autoAcceptEdits = false;
      showTurnDuration = true;

      # 每个交互式会话启动时自动连上 Remote Control(手机/浏览器接管本机会话),
      # 免得每次手动敲 /remote-control。等价于 /config 里的
      # 「Enable Remote Control for all sessions」。
      # 只有用户级(~/.claude/settings.json)和 managed settings 的 true 算数:
      # 项目级 .claude/settings.json 里写 true 会被忽略(防止仓库替所有人打开),
      # 写 false 则能就地关掉。本机这份正是用户级,所以生效。
      # 注意每个 claude 进程各注册一个远程会话;要一个进程服务多个会话得用
      # `claude remote-control` 的 server 模式,不是这个开关。
      # 依赖 feature-flag 拉取:DISABLE_TELEMETRY / DO_NOT_TRACK /
      # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC / DISABLE_GROWTHBOOK 任一开着就用不了
      # (本仓库的 env 块里都没设)。
      # 文档:https://code.claude.com/docs/en/remote-control
      remoteControlAtStartup = true;

      # 黑名单模式:bypassPermissions 下所有操作自动放行、不弹任何确认框,
      # 只有 ask 命中的操作会弹框询问(ask 规则在 bypass 模式下依然强制生效)。
      # 原来的 allow 列表在此模式下无意义,已删。
      # 注意:Bash 的规则是前缀匹配,换个写法即可绕过,防误操作可以,防不了刻意规避。
      permissions = {
        defaultMode = "bypassPermissions";
        ask = [
          # SSH 私钥同时是 agenix/sops 的解密钥,读取前先问我
          "Read(~/.ssh/**)"
        ];
      };
      # bypassPermissions 首次启动会弹一次"风险自担"确认框,这里预先接受掉
      skipDangerousModePermissionPrompt = true;
      # 控制每次请求重发的上下文体积(2026-09-23 用 tare 查一天的用量:97% 是 cache read,
      # 大头是一个上下文涨到 827K 的会话,平均每次请求重发 413K)。
      # Opus 4.7+/Sonnet 5/Fable 在官方 API 上原生 1M 窗口,默认约 967K 才 compact;
      # 钉到 300K 就是"涨到这儿自动总结一次再接着跑",不用手动 /clear。
      # 连带把空闲超过 1h(缓存 TTL)后回来那次的 cache 重写也压到 300K 以内。
      # 不用 CLAUDE_CODE_DISABLE_1M_CONTEXT:那会一刀切到 200K,且摘掉 picker 里的 1M 选项。
      # 这里写 settings 键而不是 env:env 版优先级最高,会让 `/autocompact` / `--autocompact`
      # 临时放宽这条路失效。`/autocompact` 会尝试写回 settings.json,但那是 store 里的只读文件,
      # 所以临时放宽请用 `claude --autocompact 800k`。
      # 2026-10-24 从 300K 降到 200K:30 天复查,300K 生效了(峰值 266K),但最贵的会话
      # 整段在 150K-266K 之间来回,每次请求都重发这么多;降到 200K 让长会话的重发量和
      # 空闲后的 cache 重写再少约四分之一,代价是 compact 更频繁、早期细节丢得更多。
      autoCompactWindow = 200000;
      # Bash 输出超过这个字数就落盘,Claude 只拿到 2000 字预览 + 文件路径,需要时再去读。
      # 默认 30000;同一天的 3194 次 Bash 输出里 p95 是 9.6K 字,超过 10K 的约 150 次,
      # 这批大输出占了注入总量的一成多,而且在长会话里会被每次请求重发。需要 v2.1.261+。
      bashOutputMaxChars = 10000;
      # env 里的变量会注入会话及其子进程(含 Bash 工具跑的命令和 hooks),
      # 文档:https://code.claude.com/docs/en/settings-reference#env
      # 这里刻意不写 ANTHROPIC_BASE_URL:它填的就是默认值,而 settings 的 env 会替换掉
      # 从 shell 继承的同名变量 —— 留着唯一的效果是让 `ANTHROPIC_BASE_URL=... claude`
      # 这条手动救急路径失效。要换端点走 claude-ds(见上面 mkFallbackClaude)。
      env = {
        # lark-whiteboard skill 里画板工具全是 `npx -y @larksuite/whiteboard-cli@^0.2.13`
        # 这种浮动 range 调用,默认每次都联网向 registry 解析版本(还可能漂到 0.2.x 新版)。
        # prefer-offline 让 npx 在 ~/.npm 命中缓存时直接用本地(31MB 的 dist 含预编译 skia
        # 和自带的 NotoSansSC 字体),只在缓存缺失时才联网。作用域限本会话,不动全局 ~/.npmrc。
        # 没打成 nix 包是权衡结果:73 个依赖 + native 模块要 autoPatchelf,维护成本远超收益,
        # 而且 skill 里命令写死了 npx,打了包也不会被调用。
        # 不用更狠的 npm_config_offline:实测当前缓存已能在全程禁网下跑通,但缓存一缺
        # (清了 ~/.npm、或上游 skill 把版本要求提到 0.3.x)offline 会硬失败,prefer-offline 则回落联网。
        npm_config_prefer_offline = "true";

        # 本意是跟着 services.mihomo.enable 走(mihomo 开着就开着这三行),但目前 mihomo 开着、
        # 这三行仍注释掉,原因见本段末尾。
        # tun 在 mihomo 没重启的情况下静默消失过(2026-09-12 两次),tun 一掉,API 请求就
        # 带着中国 IP 直连 api.anthropic.com —— fail-open。显式走 mixed-port 之后:
        # tun 掉了请求仍经 mihomo 的 claude 组出去;mihomo 整个挂了则连接被拒(fail-closed)。
        # mihomo 关着时不能留着:Claude 会直接连不上。
        # 终端 claude 和 VS Code 插件都读 ~/.claude/settings.json,两个入口都管得到;
        # 浏览器里的 claude.ai 管不到,tun 掉了照样漏,netloc 报 tun 不在时别开网页版。
        # 副作用:env 也注入 Bash 工具的子进程,curl/nix 等会一起走代理(国内分流规则照常生效),
        # 所以 NO_PROXY 要放过本机 —— netloc 查 127.0.0.1:9097、浏览器 MCP 连 127.0.0.1:9223。
        # 10.x 也放过:内网本来就不该绕 mihomo 一圈(tun 的 route-exclude-address 同理)。
        # 目前关着:实测带上 proxy 会影响公司 VPN 的连接,所以 Claude 只靠 tun 分流,
        # tun 掉了就是上面说的 fail-open —— 用前跑 netloc 确认 tun 在。
        # HTTPS_PROXY = "http://127.0.0.1:7897";
        # HTTP_PROXY = "http://127.0.0.1:7897";
        # NO_PROXY = "localhost,127.0.0.1,::1,10.0.0.0/8";
      };

      # KDE 桌面通知:通过 notify-send 走 D-Bus,Plasma 原生弹窗,终端和 VS Code 插件面板都生效
      # 同一事件下是数组,可以给一个事件挂多个互不影响的条目。
      hooks = {
        # config_sg 集群的 kubectl 非读取操作强制询问(见上方 kubectlGuard 注释)
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${kubectlGuard}";
              }
            ];
          }
        ];
        # Claude 需要你介入时(权限确认、空闲等待输入等)
        Notification = [
          {
            hooks = [
              {
                type = "command";
                command = ''${detectApp}; in=$(cat); msg=$(printf '%s' "$in" | ${pkgs.jq}/bin/jq -r '.message // "Claude Code needs your attention"'); case "$msg" in *"waiting for your input"*) exit 0 ;; esac; dir=$(printf '%s' "$in" | ${pkgs.jq}/bin/jq -r '.cwd // ""'); ${notifyClick} dialog-information "Claude Code ($app)" "$msg" "$dir"'';
              }
            ];
          }
        ];
        # 权限确认对话框出现时(VS Code 插件走 --permission-prompt-tool,不触发 Notification hook,只能靠这个事件)
        # 退出码 0 且无输出 = 不表态,授权对话框照常弹出,仅多发一条桌面通知
        PermissionRequest = [
          {
            hooks = [
              {
                type = "command";
                command = ''${detectApp}; in=$(cat); tool=$(printf '%s' "$in" | ${pkgs.jq}/bin/jq -r '.tool_name // "tool"'); dir=$(printf '%s' "$in" | ${pkgs.jq}/bin/jq -r '.cwd // ""'); ${notifyClick} dialog-password "Claude Code awaiting approval ($app)" "Permission needed: $tool" "$dir" -t 5000'';
              }
            ];
          }
        ];
        # Claude 完成一轮回复时:发完成通知 + 落后台子代理标记(见上方 stopHook)
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "${stopHook}";
              }
            ];
          }
        ];
        # 会话结束时清掉后台子代理标记
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "${sessionEndHook}";
              }
            ];
          }
        ];
      };
    };
  };
}
