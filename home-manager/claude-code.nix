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
      defaultMode = "plan";

      permissions = {
        allow = [
          "Read(*)"
          "Bash(find *)"
          "Bash(ls *)"
          "Bash(cat *)"
          "Bash(grep *)"
          "Bash(head *)"
          "Bash(tail *)"
          "Bash(echo *)"
          "Bash(pwd)"
          "Bash(xargs *)"
        ];
        deny = [
          "Read(~/.ssh/*)"
        ];
      };
  #     enabledPlugins = {
  #       "jdtls@claudeCodeLsps" = true;
  #     };

  #       lspServers = {
  #   jdtls = {
  #     command = "${pkgs.jdt-language-server}/bin/jdtls";
  #     args = []; # 或按需传参
  #     filetypes = [ "java" ];
  #     # 可能还有 initializationOptions、startupTimeout 等
  #   };
  # };
      env = {
        ANTHROPIC_BASE_URL = "https://api.anthropic.com";
        ENABLE_LSP_TOOL = "1";
      };
    };
  };
}
