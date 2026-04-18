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
    "terminal.integrated.profiles.linux" = {
      "zsh" = {
        "path" = "/etc/profiles/per-user/xpj/bin/zsh";
      };
    };
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
    #有些配置必须在 Default 里 
    profiles.default = {
      userSettings = {
        "workbench.colorTheme" = "Visual Studio Light";
        "dev.containers.dockerPath" = "podman";
        "update.mode" = "none";
        "dev.containers.dockerComposePath" = "podman-compose";
      };
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
        eamodio.gitlens
        ms-vscode-remote.remote-containers
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
    profiles.markdown = {
      extensions = with pkgs.vscode-marketplace; [
        natqe.reload
        shd101wyy.markdown-preview-enhanced
      ];
      userSettings = vscodeBaseSettings;
    };
  };
}
