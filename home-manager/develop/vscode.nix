{
  pkgs,
  ...
}:
let
  # 定义所有 profile 共用的基础配置
  vscodeBaseSettings = {
    "workbench.colorTheme" = "Visual Studio Light";
    # 整体缩放界面：1 = 放大 20%，1.5 = 30%，2 = 44%，按需调整
    # "window.zoomLevel" = 1.5;
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

  # Claude Code 扩展的权限模式独立于 ~/.claude/settings.json:
  # 必须先打开 allowDangerouslySkipPermissions,initialPermissionMode 的
  # bypassPermissions 才生效,否则扩展会静默回落到 Manual 模式、每次编辑都弹确认框。
  # 与 claude-code.nix 的 defaultMode = "bypassPermissions" 对齐,
  # settings.json 里的 ask 规则(SSH 私钥)和 kubectl hook 兜底在扩展里依然生效。
  claudeCodeSettings = {
    "claudeCode.preferredLocation" = "panel";
    "claudeCode.initialPermissionMode" = "bypassPermissions";
    "claudeCode.allowDangerouslySkipPermissions" = true;
  };
in
{

  programs.vscode = {
    enable = true;

    #有些配置必须在 Default 里
    profiles.default = {
      userSettings = {
        "workbench.colorTheme" = "Visual Studio Light";
        # "window.zoomLevel" = 1.5;
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
      userSettings = vscodeBaseSettings // claudeCodeSettings // {
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

      userSettings = vscodeBaseSettings // claudeCodeSettings;
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
      userSettings = vscodeBaseSettings // claudeCodeSettings;
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
