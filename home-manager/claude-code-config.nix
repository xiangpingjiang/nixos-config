# modules/claude-code.nix
{
  ...
}:
{
  # home.nix 或单独的 claude.nix
  home.file.".claude/settings.json" = {
    text = builtins.toJSON {
      # 模型选择
      model = "claude-sonnet-4-6";

      # 权限控制
      # permissions = {
      #   allow = [
      #     "Bash(git *)"
      #     "Bash(cargo *)"
      #     "Bash(npm *)"
      #     "Read(**)"
      #   ];
      #   deny = [
      #     "Bash(rm -rf *)"
      #   ];
      # };

      # 注入环境变量（适合设置 API base URL 等）
      env = {
        ANTHROPIC_BASE_URL = "https://api.anthropic.com";
        # 注意：API key 不要硬编码，见下方 agenix 方案
      };

      # 自动接受编辑（慎用）
      autoAcceptEdits = false;

      # 显示每次响应耗时
      showTurnDuration = true;

      # hooks：保存后自动格式化
      # hooks = {
      #   PostToolUse = [
      #     {
      #       matcher = "Edit|Write";
      #       hooks = [
      #         {
      #           type = "command";
      #           command = "nixfmt $CLAUDE_TOOL_OUTPUT_FILE 2>/dev/null || true";
      #         }
      #       ];
      #     }
      #   ];
      # };
    };
  };
}
