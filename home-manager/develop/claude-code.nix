{
  inputs,
  pkgs,
  lib,
  config,
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

  # Claude Code Agent Monitor(CCAM):本地实时监控面板,hooks 把每个事件 POST 到
  # 127.0.0.1:4820 的 Express+SQLite 服务,浏览器端走 WebSocket 实时刷新。
  # 上游装 hooks 的两个入口在这台机器上都失效——`npm run install-hooks` 和 server
  # 启动时的自动安装都是 writeFileSync(~/.claude/settings.json),而这个文件是
  # home-manager 生成的 /nix/store 只读符号链接(server 那次包在 try/catch 里静默
  # 失败,不影响服务本身)。所以 hooks 只能像下面这样声明式写进来。
  #
  # 源码有意放可变目录而不是 fetchFromGitHub 钉进 store:上游几天一个版本,钉 store
  # 每次升级都要重算根和 client 两份 npmDepsHash。代价是升级不走 home-manager switch:
  #   cd ~/.local/share/ccam && git pull && npm install && npm run build
  #   systemctl --user restart ccam-dashboard
  ccamRoot = "${config.home.homeDirectory}/.local/share/ccam";

  # hook 侧的依赖闭包(hook-handler → hook-transport → server/lib/{server-info,claude-home})
  # 只用 node 内置模块,完全不碰 node_modules,所以这里只需要 nodejs + 源码文件。
  # 行为是 fire-and-forget:请求超时 2s、进程 2.5s 硬退出、不往 stdout 写任何东西,
  # 面板没启动时立刻 ECONNREFUSED 返回。既不会拖慢会话,也不会干扰权限决策
  # (hook 的 stdout JSON 才有决策语义,它不输出就不参与)。
  # 代价:PreToolUse/PostToolUse 是 matcher "*",每次工具调用多两次 node 进程启动。
  ccamHook = event: {
    type = "command";
    command = ''${pkgs.nodejs}/bin/node "${ccamRoot}/scripts/hook-handler.js" ${event}'';
  };
in
{
  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    # skill 不在这里声明:统一交给 agent-skills-nix 管理(见 ./agent-skills.nix)

    # 多模型分工(写入全局 ~/.claude/CLAUDE.md):
    # Claude Code 没有内置的"按难度自动换模型"路由(model-config 文档确认),
    # 所以只剩一条路:主会话跑 Fable,再由主模型用 Agent 工具把机械/常规工作分流给
    # 更便宜的 haiku/sonnet(Agent 的 model 参数;/model 只有用户能手动执行)。
    # 2026-09-02 之前是"Opus 主会话 + Fable advisor",现在 Fable 直接当主模型、
    # advisor 一并删掉(理由见 settings 里的注释)。
    # 改本文件前先查官方文档:https://code.claude.com/docs/(页面索引在 /docs/llms.txt)
    #
    # 后两节(回答风格 / 工具使用)是评估 caveman、context-mode 两个 token 优化项目后的留存物。
    # 实测本机近 30 天:assistant output 里 72% 的字符是工具参数和代码(这类项目一律不压),
    # 散文只占 22%;tool_result 里 MCP 只占 1.09%,大头是 Read(59%)和 Bash(37%)。
    # 两者的招牌收益(caveman 的 65%、context-mode 的 98%)都落不到本机,不值得装,
    # 但各有一条规则有真实增量,直接写进 context:零安装,也不额外占 context(本文件本来就常驻)。
    context = ''
      # 模型分工策略(节省 token 费用)

      主会话运行在 Fable,没有配 advisor:advisor 要求它不弱于主模型,主会话已经是 Fable
      时它只能是"另一个 Fable 复核",每次还要完整重读对话且不走缓存,不划算。
      所以省钱全靠往下委派:

      - **haiku(Agent 工具委派,显式传 model 参数)** —— 机械性工作:
        代码/文件搜索(配 Explore agent)、批量小改动、跑命令并汇总输出、
        格式转换、按明确清单执行的操作。
      - **sonnet(Agent 工具委派,显式传 model 参数)** —— 常规子任务:
        普通编码修改、写测试、常见 bug 修复、资料调研与总结。
      - **主会话自己做(fable)** —— 需要较强推理或完整上下文的工作:
        方案设计、疑难 debug、跨文件改动的把关与收尾。

      规则:
      - 主会话每一轮都按 Fable 计费,是全场最贵的一档,能下放的就下放:
        搜索、批量改动、跑命令看输出这类活儿默认交给 haiku/sonnet,不要自己埋头做。
      - 委派时把上下文和验收标准写全,避免便宜模型来回试错反而更费 token。
      - 子代理跑在隔离上下文里:看不到当前对话,只拿得到 prompt 里写的东西,中途也无法
        追加信息,所以只在任务能一次性描述清楚时委派;打不包的就自己做。
      - 一两步就能完成的事不必委派,直接做(委派本身也有开销)。
      - 便宜模型返回的结果要过目,不放心的部分自己复核,不要盲信。

      # 回答风格

      - 不写工具调用旁白(「我来看一下…」「接下来我要…」),直接调用。
      - 不用装饰性表格和 emoji;表格只在真的是二维数据时用。
      - 不整段贴报错日志,引用最关键的那一两行;完整日志用户需要时再给。

      # 工具使用

      - 读大文件先用 `sed -n '起,止p'` 或 `grep -n` 取相关段落,确认需要全文再整文件读。
    '';

    settings = {
      # 主会话直接跑 Fable。写别名而不是 claude-fable-5-1:别名解析到 Claude Code 内置的
      # 最新 Fable,实测 2.1.258 上就是 claude-fable-5-1,要复验跑:
      #   claude --model fable -p hi --output-format json | jq '.modelUsage | keys'
      # 前提:Fable 5.1 需要 Claude Code 2.1.255+,终端和插件两份二进制都得够版本
      # (见 CLAUDE.md「Claude Code 有两份互不相干的二进制」)。
      # 不配 advisorModel:advisor 必须不弱于主模型,Fable 5.1 主模型只接受 Fable 5.1
      # (Opus/Sonnet 一律被拒),等于"另一个 Fable 复核",而每次调用都要完整重读对话
      # 且不走缓存——官方文档也是这个口径:每轮都需要最强模型就直接换主模型,别挂 advisor。
      # 文档:https://code.claude.com/docs/en/advisor 与 /docs/en/model-config
      # 注意:部分订阅计划下 Fable 走 usage credits,首次需在会话里 /model fable 同意一次。
      model = "fable";
      language = "chinese";
      autoAcceptEdits = false;
      showTurnDuration = true;

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
      env = {
        ANTHROPIC_BASE_URL = "https://api.anthropic.com";
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
      # 同一事件下是数组,CCAM 的上报条目和这里原有的通知/守卫条目并存互不影响
      # (CCAM 的 matcher "*" 与 kubectl 守卫的 matcher "Bash" 也可以共存)。
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
          {
            matcher = "*";
            hooks = [ (ccamHook "PreToolUse") ];
          }
        ];
        # 以下几个事件只用于 CCAM 上报
        PostToolUse = [
          {
            matcher = "*";
            hooks = [ (ccamHook "PostToolUse") ];
          }
        ];
        SubagentStop = [
          {
            matcher = "*";
            hooks = [ (ccamHook "SubagentStop") ];
          }
        ];
        # SessionStart / SessionEnd / UserPromptSubmit 不接受 tool-name matcher。
        # UserPromptSubmit 是纯文本轮次里唯一可靠的"用户已恢复"信号——不调工具时
        # 不会有 PreToolUse,缺了它面板的 Waiting 状态会一直挂着。
        SessionStart = [ { hooks = [ (ccamHook "SessionStart") ]; } ];
        SessionEnd = [ { hooks = [ (ccamHook "SessionEnd") ]; } ];
        UserPromptSubmit = [ { hooks = [ (ccamHook "UserPromptSubmit") ]; } ];
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
          {
            matcher = "*";
            hooks = [ (ccamHook "Notification") ];
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
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = ''${detectApp}; dir=$(${pkgs.jq}/bin/jq -r '.cwd // ""'); ${notifyClick} dialog-ok "Claude Code task complete ($app)" "Project: $(basename "$dir")" "$dir"'';
              }
            ];
          }
          {
            matcher = "*";
            hooks = [ (ccamHook "Stop") ];
          }
        ];
      };
    };
  };

  # CCAM 面板服务:单进程在 4820 端口同时提供 API/WebSocket 和构建好的前端(client/dist),
  # 打开 http://localhost:4820 即可,不用一直挂着终端。
  # SQLite 后端走 Node 24 内置的 node:sqlite:better-sqlite3 只是 optionalDependency,
  # 而新版 npm 默认不执行依赖的 install script,它的 native 二进制没编译,正好用不上,
  # 也就绕开了 NixOS 上 prebuild-install 二进制跑不起来的老问题。
  # ConditionPathExists:源码目录不在(还没 clone / 挪走了)就跳过启动而不是反复失败。
  systemd.user.services.ccam-dashboard = {
    Unit = {
      Description = "Claude Code Agent Monitor dashboard";
      After = [ "network.target" ];
      ConditionPathExists = "${ccamRoot}/server/index.js";
    };
    Service = {
      WorkingDirectory = ccamRoot;
      ExecStart = "${pkgs.nodejs}/bin/node server/index.js";
      # git/openssh 供面板的更新检查和 Remote Data Sources 调用。
      # claude 和 which 必须在这里显式给出:PATH 是完全覆盖的(systemd user service
      # 不继承登录 shell 的环境),而面板 Run 页面用 spawnSync("which", ["claude"])
      # 探测后才 spawn 会话——少任何一个都报 "The `claude` CLI isn't on your PATH"
      # (缺 which 时 spawnSync 直接 ENOENT,报错和 claude 真的不存在时一模一样)。
      # 引用 programs.claude-code.package 而不是 ~/.nix-profile/bin,保证和会话用的是同一版本。
      Environment = [
        "NODE_ENV=production"
        "PATH=${
          lib.makeBinPath [
            pkgs.nodejs
            pkgs.git
            pkgs.openssh
            pkgs.which
            config.programs.claude-code.package
          ]
        }"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
