{
  ...
}:

let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
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
      home.stateVersion = "26.05";
      nixpkgs.config.allowUnfree = true;

      imports = [
        ./plasma.nix
        ./rclone.nix
        "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/modules/age-home.nix"
        ./secrets.nix
        ./vscode.nix
      ];

      programs = {
        ghostty = {
          enable = true;
          settings = {
            # shell-integration = zsh;
            command = "/run/current-system/sw/bin/zsh";
            theme = "Tomorrow Night Eighties";
            # font-size = 10;
            # keybind = [
            #   "ctrl+h=goto_split:left"
            #   "ctrl+l=goto_split:right"
            # ];
          };
        };

        obsidian = {
          enable = true;
        };
      };

      services = {
        podman = {
          enable = true;
          settings.policy = {
            default = [ { type = "insecureAcceptAnything"; } ];
          };
        };
      };

    };
}
