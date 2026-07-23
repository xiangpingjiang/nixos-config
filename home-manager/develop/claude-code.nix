{
  inputs,
  pkgs,
  ...
}:
# let
#   claudeCodeLsps = pkgs.fetchFromGitHub {
#     owner = "Piebald-AI";
#     repo = "claude-code-lsps";
#     rev = "main"; # 建议换成具体 commit hash 锁定版本
#     sha256 =  "sha256-DipPgDgRMYreqMkeNQRtTk7zXRUm/4i9zZpjMrVW8zQ="; #pkgs.lib.fakeHash 第一次 build 报错后替换为正确 hash
#   };
# in

let
  # 识别通知来源:VS Code 扩展下 CLAUDE_CODE_ENTRYPOINT=claude-vscode,终端 CLI 下为 cli
  # (不能用 TERM_PROGRAM,它会从启动 VS Code 的终端继承,导致误判)
  detectApp = ''case "$CLAUDE_CODE_ENTRYPOINT" in *vscode*) app="VS Code" ;; *) app="Terminal" ;; esac'';
in
{
  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    # plugins = [
    #   "${claudeCodeLsps}/jdtls"
    # ];

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
      # enabledPlugins = {
      #   "jdtls-lsp@claude-plugins-official" = true;
      # };
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
                command = ''${detectApp}; msg=$(${pkgs.jq}/bin/jq -r '.message // "Claude Code needs your attention"'); ${pkgs.libnotify}/bin/notify-send -a "Claude Code" -i dialog-information "Claude Code ($app)" "$msg"'';
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
                command = ''${detectApp}; dir=$(${pkgs.jq}/bin/jq -r '.cwd // ""'); ${pkgs.libnotify}/bin/notify-send -a "Claude Code" -i dialog-ok "Claude Code task complete ($app)" "Project: $(basename "$dir")"'';
              }
            ];
          }
        ];
      };
    };
  };
}
