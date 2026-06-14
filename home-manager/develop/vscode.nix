{
  pkgs,
  ...
}:
let
  # 定义所有 profile 共用的基础配置
  vscodeBaseSettings = {
    "workbench.colorTheme" = "Visual Studio Light";
    "terminal.integrated.defaultProfile.linux" = "zsh";
    "terminal.integrated.profiles.linux" = {
      "zsh" = {
        "path" = "${pkgs.zsh}/bin/zsh";
      };
    };
    "chat.disableAIFeatures" = true;
    "extensions.ignoreRecommendations" = true;
    "chat.agent.enabled" = false;
    "terminal.integrated.tabs.allowAgentCliTitle" = false;
  };
in
{

  programs.vscode = {
    enable = true;

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
      extensions = pkgs.nix4vscode.forVscode [
        "jnoortheen.nix-ide"
        "natqe.reload"
        "kdl-org.kdl"
      ];
      userSettings = vscodeBaseSettings // {
        "nix.enableLanguageServer" = true;
        "editor.formatOnSave" = true;
        "nix.serverPath" = "nil";
        "nix.serverSettings.nil" = {
          "formatting" = {
            "command" = [ "nixfmt" ];
          };

        };
      };
    };
    profiles.python = {
      extensions = pkgs.nix4vscode.forVscode [
        "ms-python.debugpy"
        "ms-python.vscode-pylance"
        "ms-python.python"
        "natqe.reload"
        "eamodio.gitlens"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.golang = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "golang.go"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.typst = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "myriad-dreamin.tinymist"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.markdown = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "shd101wyy.markdown-preview-enhanced"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.jsonnet = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "grafana.vscode-jsonnet"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.java = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "vscjava.vscode-java-pack"
        "redhat.java"
        "vscjava.vscode-java-debug"
        "vscjava.vscode-java-test"
        "vscjava.vscode-maven"
        "vscjava.vscode-java-dependency"
        "eamodio.gitlens"
      ];
      userSettings = vscodeBaseSettings;
    };
    profiles.ssh = {
      extensions = pkgs.nix4vscode.forVscode [
        "ms-vscode-remote.remote-ssh"
        "ms-vscode.remote-explorer"
        "natqe.reload"
      ];

      userSettings = vscodeBaseSettings;
    };
    profiles.dev_container = {
      extensions = pkgs.nix4vscode.forVscode [
        "ms-vscode-remote.remote-containers"
        "ms-kubernetes-tools.vscode-kubernetes-tools"
        "redhat.vscode-yaml"
        "natqe.reload"
      ];
      userSettings = vscodeBaseSettings;
    };
  };
}
