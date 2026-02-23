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

        vscode = {
          enable = true;
          profiles.nix = {
            extensions = with pkgs.vscode-extensions; [
              jnoortheen.nix-ide
              natqe.reload
            ];
            userSettings = {
              "workbench.colorTheme" = "Visual Studio Light";
              "nix.enableLanguageServer" = true;
              "nix.serverPath" = "nil";
              "nix.serverSettings.nil" = {
                "formatting" = {
                  "command" = [ "nixfmt" ];
                };

              };
            };
          };
          profiles.python = {
            extensions = with pkgs.vscode-extensions; [
              ms-python.debugpy
              ms-python.vscode-pylance
              ms-python.python
              natqe.reload
            ];
            userSettings = {
              "workbench.colorTheme" = "Visual Studio Light";
            };
          };
          profiles.golang = {
            extensions = with pkgs.vscode-extensions; [
              natqe.reload
              golang.go
            ];
            userSettings = {
              "workbench.colorTheme" = "Visual Studio Light";
            };
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
