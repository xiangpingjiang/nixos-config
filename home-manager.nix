{
  config,
  pkgs,
  lib,
  ...
}:

let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz";
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];
  home-manager.backupFileExtension = "backup";

  home-manager.users.xpj =
    { pkgs, ... }:
    {

      # The state version is required and should stay at the version you
      # originally installed.
      home.stateVersion = "25.11";

      programs = {
        ghostty = {
          enable = true;
          settings = {
            # shell-integration = zsh;
            command = "/run/current-system/sw/bin/zsh";
            # theme = "catppuccin-mocha";
            # font-size = 10;
            # keybind = [
            #   "ctrl+h=goto_split:left"
            #   "ctrl+l=goto_split:right"
            # ];
          };
        };
      };
    };
}
