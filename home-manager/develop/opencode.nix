{
  inputs,
  pkgs,
  ...
}:

{
  programs.opencode = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    tui = {
      theme = "everforest";
    };
    settings = {

      lsp = true;
    };
  };
}
