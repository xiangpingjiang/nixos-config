{
  pkgs,
  ...
}:
let
  # 定义所有 profile 共用的基础配置
  vscodeBaseSettings = {
    "workbench.colorTheme" = "Visual Studio Light";
    # 整体缩放界面：1 = 放大 20%，1.5 = 30%，2 = 44%，按需调整
    "window.zoomLevel" = 1.5;
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
        "window.zoomLevel" = 1.5;
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
        "anthropic.claude-code"
      ];
      userSettings = vscodeBaseSettings // {
        "claudeCode.preferredLocation" = "panel";
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
        "mk12.better-git-line-blame"
        "anthropic.claude-code"
      ];

      userSettings = vscodeBaseSettings // {
        "claudeCode.preferredLocation" = "panel";
      };
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
        "foam.foam-vscode"
        "anthropic.claude-code"
      ];
      userSettings = vscodeBaseSettings // {
        "claudeCode.preferredLocation" = "panel";
      };
    };
    profiles.jsonnet = {
      extensions = pkgs.nix4vscode.forVscode [
        "natqe.reload"
        "grafana.vscode-jsonnet"
        "mk12.better-git-line-blame"
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
        "mk12.better-git-line-blame"
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
    profiles.sql = {
      extensions = pkgs.nix4vscode.forVscode [
        "mtxr.sqltools"
        "mtxr.sqltools-driver-mysql"
        "ultram4rine.sqltools-clickhouse-driver"
        "natqe.reload"
      ];
      userSettings = vscodeBaseSettings;
    };
  };
}
