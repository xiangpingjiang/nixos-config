{
  inputs,
  pkgs,
  ...
}:

{
  programs.codex = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
    # 0.159 起 TUI 默认起后台 app-server daemon,它要求带 codex-package.json 的安装包布局,
    # nix 打的包没有,会报 "this CLI has no complete local package"。
    # 已在 ~/.codex/config.toml(可变文件,codex 自己会写 trust,不交给 settings 管)里加了
    # [features] daemon_auto_start = false,走内嵌 server。换机器要手动补这两行。

  };
}
