{
  inputs,
  pkgs,
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
in
{
  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    # dbx 官方 skill,直接取自 flake input 源码,随 `nix flake update` 更新。
    # 前提:PATH 里的 dbx 是 CLI(见 home.nix 的 dbx-cli/dbx-desktop 命名安排)
    skills.dbx = "${inputs.dbx}/skills/dbx";

    settings = {
      model = "claude-fable-5";
      language = "chinese";
      autoAcceptEdits = false;
      showTurnDuration = true;

      permissions = {
        allow = [
          "Read(/home/xpj/Projects/**)"
          "Read(/home/xpj/.m2/**)"
          "Bash(find **)"
          "Bash(grep **)"
          "Bash(echo **)"
          "Bash(pwd)"
          "Bash(xargs **)"
        ];
        deny = [
          "Read(~/.ssh/**)"
        ];
      };
      env = {
        ANTHROPIC_BASE_URL = "https://api.anthropic.com";
      };

      # KDE 桌面通知:通过 notify-send 走 D-Bus,Plasma 原生弹窗,终端和 VS Code 插件面板都生效
      hooks = {
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
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = ''${detectApp}; dir=$(${pkgs.jq}/bin/jq -r '.cwd // ""'); ${notifyClick} dialog-ok "Claude Code task complete ($app)" "Project: $(basename "$dir")" "$dir"'';
              }
            ];
          }
        ];
      };
    };
  };
}
