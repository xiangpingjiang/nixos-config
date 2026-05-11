{
  inputs,
  pkgs,
  config,
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

{
  programs.claude-code = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    # plugins = [
    #   "${claudeCodeLsps}/jdtls"
    # ];

    settings = {
      model = "claude-sonnet-4-6";
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
      enabledPlugins = {
        "jdtls-lsp@claude-plugins-official" = true;
      };
      env = {
        ANTHROPIC_BASE_URL = "https://api.anthropic.com";
      };
    };
  };
}
