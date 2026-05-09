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

let
  claude-code-orig = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  claude-code-wrapped = pkgs.writeShellScriptBin "claude" ''
    export ANTHROPIC_AUTH_TOKEN="$(cat ${config.age.secrets.deepseek_api_key.path})"
    exec ${claude-code-orig}/bin/claude "$@"
  '';
in
{
  programs.claude-code = {
    enable = true;
    package = claude-code-wrapped;
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
        # ANTHROPIC_BASE_URL = "https://api.anthropic.com";

        ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic";
        ANTHROPIC_MODEL = "deepseek-v4-pro";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro";
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash";
        CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-v4-flash";
        CLAUDE_CODE_EFFORT_LEVEL = "max";
      };
    };
  };

  # 暂时不需要

  # home.file.".claude-code-router/config.json" = {
  #   text = builtins.toJSON {
  #     HOST = "0.0.0.0";
  #     PORT = 8080;
  #     Providers = [
  #       {
  #         name = "deepseek";
  #         api_base_url = "https://api.openai.com/v1/chat/completions";
  #         api_key = "your-api-key-here";
  #         models = [
  #           "gpt-4"
  #           "gpt-3.5-turbo"
  #         ];
  #       }
  #     ];
  #     Router = {
  #       default = "deepseek";
  #     };
  #   };
  # };
}
