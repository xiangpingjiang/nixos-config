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
  # 局限:通知过期进入 Plasma 历史后,发送进程已退出,从历史里点不会再跳转。
  notifyClick = pkgs.writeShellScript "claude-notify-click" ''
    exec ${pkgs.util-linux}/bin/setsid -f ${pkgs.bash}/bin/bash -c '
      icon="$1"; title="$2"; body="$3"; dir="$4"; shift 4
      action=$(${pkgs.libnotify}/bin/notify-send -a "Claude Code" -i "$icon" -A default=打开 "$@" "$title" "$body")
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
                case "$tok" in
                  # 只读子命令白名单,其余一律视为需要询问
                  get|describe|logs|top|events|explain|version|api-resources|api-versions|cluster-info|auth|diff|wait|completion) ;;
                  *) bad=$tok ;;
                esac
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
  claudeCodeVersion = "2.1.268";
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
          hash = "sha256-lpGit715ZxLKjP+44y5U/3/EW2YlQCMxcaFqlKBCVlM=";
        };
      });
  # 跨窗口列出活跃的 Claude Code 会话(zellij 的 cc tab 循环跑的就是它,见 zellij/dev.kdl)。
  # 用 writeShellApplication 而不是 writeShellScriptBin:前者过 shellcheck,并且能用
  # runtimeInputs 固定 PATH —— 进程枚举和 transcript 解析都在 claude-sessions.py 里,
  # 所以只需要 python3(标准库,无第三方依赖)和 coreutils;zellij 的 command pane
  # 不经过 shell,PATH 取决于 zellij 服务端从哪里起的,不能指望调用者的环境。
  # bashOptions 显式去掉默认的 errexit:新开的会话命令行里没有 --resume,
  # `sid=$(... | grep -oP ...)` 无匹配返回 1 是正常路径,-e 下会当场终止整个脚本。
  # 渲染器单独成包放进 profile 的 share/,好让 --watch 面板能走一条跨代稳定的路径:
  # 面板是个长命进程,bash 启动时就把当时那份 store 脚本读进去了,之后 home-manager
  # switch 换代它完全不知道 —— 2026-09-09 就是这么"检测又不准"的:两个面板分别停在
  # 09-04 / 09-08 的渲染器上,少了 09-08 那次 first_epoch 修复,终端会话永远显示"尚未对话"。
  # 逻辑全在渲染器里,所以让它每轮从 ~/.nix-profile 重新解析,switch 完立刻生效、不用重启 pane;
  # 驱动那半(取宽度/差分重绘/按键)改动少,陈旧了影响也有限,仍然只在重启 pane 时更新。
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
  # 四个模型别名都要映射。全局 CLAUDE.md 让主模型按 haiku/sonnet/fable 委派子代理,
  # 漏掉 fable 那条委派路径会当场撞未知模型(DeepSeek 官方那份配置里没有 fable)。
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
    ccSessionsRender
    claudeDeepseek
  ];

  programs.claude-code = {
    enable = true;
    package = claudeCodePkg;

    # skill 不在这里声明:统一交给 agent-skills-nix 管理(见 ./agent-skills.nix)

    # 多模型分工(写入全局 ~/.claude/CLAUDE.md):
    # Claude Code 没有内置的"按难度自动换模型"路由(model-config 文档确认),
    # 这里组合两个机制:主会话跑 Opus + Fable 做 advisor(见 settings.advisorModel),
    # 再由主模型用 Agent 工具分流:机械/常规工作给更便宜的 haiku/sonnet,
    # 能一次性描述清楚的整块大活儿给 fable 子代理(Agent 的 model 参数;
    # /model 只有用户能手动执行)。
    # 2026-09-02 曾切成"Fable 主会话、不配 advisor",当天又切回来:Fable 主模型
    # 只接受 Fable 做 advisor,等于每一轮都跑最贵的模型还分不了层,与省钱目标相悖。
    #
    # 2026-09-12 把 fable 那条的门槛从"高难度"改成"工作量和范围",并加了"拿不准
    # 也优先给它"。起因是查用量时发现 Fable 池一周只用到 2% —— 委派条件写成
    # "大型重构 / 疑难 debug / 深度调研",而本机最近 40 个会话中位只有 51 轮、
    # 内容以查日志跑 SQL 读代码为主,没有一个够得上那个门槛,于是这条通道形同虚设。
    # 官方对 Fable 的定位本来也是"长自主任务"(长度和自主性)而不是"难题",
    # 按范围判比按难度判更贴合,也更容易触发。
    # 同时记一条文档事实:子代理继承 advisorModel,fable 子代理会带着 fable advisor
    # (合法配对,但双倍消耗且更慢),所以 context 里要求委派时在 prompt 注明别再咨询。
    # 改本文件前先查官方文档:https://code.claude.com/docs/(页面索引在 /docs/llms.txt)
    #
    # 后两节(回答风格 / 工具使用)是评估 caveman、context-mode 两个 token 优化项目后的留存物。
    # 实测本机近 30 天:assistant output 里 72% 的字符是工具参数和代码(这类项目一律不压),
    # 散文只占 22%;tool_result 里 MCP 只占 1.09%,大头是 Read(59%)和 Bash(37%)。
    # 两者的招牌收益(caveman 的 65%、context-mode 的 98%)都落不到本机,不值得装,
    # 但各有一条规则有真实增量,直接写进 context:零安装,也不额外占 context(本文件本来就常驻)。
    context = ''
      # 模型分工策略(把活儿分到对的模型和用量池)

      主会话运行在 Opus,并配置了 Fable 作为 advisor。Opus 和 Fable 各有自己的用量
      上限,**Fable 那个池子长期闲置**(实测一周只用到 2%,几乎全是 advisor 触发的)。
      所以这套分工有两个方向:往下把机械活儿卸给 haiku/sonnet,往上把够格的大活儿
      推给 fable —— 后者一直没被用起来,是当前的短板。分工原则:

      - **advisor(Fable)** —— 关键决策点主动咨询:确定技术方案前、
        同一错误反复出现时、宣布任务完成前、安全/密钥相关改动前。
        它能看到完整对话;注意每次咨询都会完整重读对话且不走缓存,别滥用。
      - **haiku(Agent 工具委派,显式传 model 参数)** —— 机械性工作:
        代码/文件搜索(配 Explore agent)、批量小改动、跑命令并汇总输出、
        格式转换、按明确清单执行的操作。
      - **sonnet(Agent 工具委派,显式传 model 参数)** —— 常规子任务:
        普通编码修改、写测试、常见 bug 修复、资料调研与总结。
      - **fable(Agent 工具委派,显式传 model 参数)** —— 整块的、能一次性描述清楚的
        大活儿。判据是**工作量和范围**,不是"难不难":跨多个文件的改动、成体系的调研、
        需要反复验证的迁移、一次要读十几个文件才讲得清的排查,都够格。官方对 Fable 的
        定位就是长自主任务(行动前先调查、更频繁地验证自己的工作),不必等到"疑难"
        才想起它。这是唯一不需要用户手动 /model 就能让 Fable 干活的路径,
        由主模型自己判断是否启用。
      - **主会话自己做(opus)** —— 需要较强推理或完整上下文的工作:
        方案设计、复杂 debug、跨文件改动的把关与收尾。

      规则:
      - 主会话每一轮都按 Opus 计费,能下放的就下放:搜索、批量改动、跑命令看输出
        这类活儿默认交给 haiku/sonnet,不要自己埋头做。
      - 委派时把上下文和验收标准写全,避免便宜模型来回试错反而更费 token。
      - 子代理跑在隔离上下文里:看不到当前对话,只拿得到 prompt 里写的东西,中途也无法
        追加信息,所以只在任务能一次性描述清楚时委派;打不包的就自己做。
      - 一两步就能完成的事不必委派,直接做(委派本身也有开销)。
      - 便宜模型返回的结果要过目,不放心的部分自己复核,不要盲信。
      - 遇到整块的大活儿,先判断能否一次性描述清楚:能就委派给 fable 子代理;
        打不包(需要边做边对齐、依赖当前对话上下文)就自己做并在决策点咨询 advisor。
        **不要为了"省"而自己硬扛或降级给 sonnet** —— 那既慢、又占 Opus 的额度,
        而 Fable 是当前最不缺的那个池子。够格就给它,拿不准也优先给它。
      - 给 fable 子代理的 prompt 里注明"不必再咨询 advisor":子代理会继承
        advisorModel = fable(文档:Subagents inherit the configured advisor),
        Fable 主 + Fable advisor 是合法配对,但等于双倍消耗还拖慢它,
        而这种一次性打包出去的任务本来就不需要中途复核。

      # 回答风格

      - 不写工具调用旁白(「我来看一下…」「接下来我要…」),直接调用。
      - 不用装饰性表格和 emoji;表格只在真的是二维数据时用。
      - 不整段贴报错日志,引用最关键的那一两行;完整日志用户需要时再给。

      # 工具使用

      - 读大文件先用 `sed -n '起,止p'` 或 `grep -n` 取相关段落,确认需要全文再整文件读。
    '';

    settings = {
      # 主会话 Opus + Fable advisor:日常轮次按 Opus 计费,Claude 只在关键决策点
      # 自己决定咨询 Fable。触发时机完全由模型判断,没有任何设置项能强制、限频或按
      # 规则触发,只能靠上面 context 里的指令引导;临时需要时在对话里说"先咨询 advisor"。
      # advisor 是实验特性,仅 Anthropic API 直连可用,且依赖 feature-flag 拉取——
      # 设 DISABLE_TELEMETRY 会让它失效。
      # 配对约束:advisor 必须不弱于主模型。Opus 4.7+ 主模型接受 Fable 或 Opus 4.7+;
      # 反过来 Fable 主模型只接受 Fable,所以"Fable 主 + 更弱 advisor 分层"这条路不存在。
      # 别名 fable 解析到 Claude Code 内置的最新 Fable(2.1.255+ 上是 claude-fable-5-1),
      # 终端和插件两份二进制都得 ≥2.1.255(见 CLAUDE.md「Claude Code 有两份互不相干的二进制」)。
      # 文档:https://code.claude.com/docs/en/advisor 与 /docs/en/model-config
      # 注意:部分订阅计划下 Fable 走 usage credits,首次需在会话里 /model fable 同意一次,
      # 之后 advisor 才会真正生效(本机已同意过)。
      model = "opus";
      advisorModel = "fable";
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
        # Claude 完成一轮回复时
        # 会话里还有 running 的后台子代理时不发:它结束会把会话重新唤醒接着干,
        # 这一次 Stop 只是中途停顿(实测一次提问因此触发了 3 次 Stop,最终那次
        # background_tasks 才是 [])。判据刻意收窄到 type=="subagent",不写
        # `background_tasks | length > 0`:后台 shell 可以是 dev server 这种不退出的进程,
        # 那样整个会话就再也收不到通知了;子代理则必定结束、必定唤醒。
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = ''${detectApp}; in=$(cat); [ "$(printf '%s' "$in" | ${pkgs.jq}/bin/jq '[.background_tasks[]? | select(.type == "subagent" and .status == "running")] | length')" = "0" ] || exit 0; dir=$(printf '%s' "$in" | ${pkgs.jq}/bin/jq -r '.cwd // ""'); ${notifyClick} dialog-ok "Claude Code task complete ($app)" "Project: $(basename "$dir")" "$dir"'';
              }
            ];
          }
        ];
      };
    };
  };
}
