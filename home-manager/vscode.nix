{
  pkgs,
  ...
}:
let
  nix-vscode-extensions = import (
    builtins.fetchGit {
      url = "https://github.com/nix-community/nix-vscode-extensions";
      ref = "refs/heads/master";
      rev = "c22e7adea9adec98b3dc79be954ee17d56a232bd";
    }
  );

  # 定义所有 profile 共用的基础配置
  vscodeBaseSettings = {
    "workbench.colorTheme" = "Visual Studio Light";
    "terminal.integrated.defaultProfile.linux" = "zsh";
  };
in
{

  nixpkgs.overlays = [
    nix-vscode-extensions.overlays.default
  ];
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.override {
      commandLineArgs = [
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        "--"
      ];
    };
    profiles.nix = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        natqe.reload
      ];
      userSettings = vscodeBaseSettings // {
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
      userSettings = vscodeBaseSettings;
    };
    profiles.golang = {
      extensions = with pkgs.vscode-extensions; [
        natqe.reload
        golang.go
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.typst = {
      extensions = with pkgs.vscode-marketplace; [
        natqe.reload
        myriad-dreamin.tinymist
      ];
      userSettings = vscodeBaseSettings;
    };
  };
}
