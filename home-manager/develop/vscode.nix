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
    # 每 180s(git.autofetchPeriod 默认值)自动 fetch。scope 是 resource 而非
    # application,所以每个 profile 的 user settings 都要各自声明才生效——
    # 只写进 profiles.default 的话,切到别的 profile 就没有了。
    "git.autofetch" = true;
  };

  # Claude Code 扩展不走 nix4vscode:它的插件数据每天只在 02:10-02:30 UTC 生成一次
  # (见 CLAUDE.md 的更新窗口一节),新版本到得慢——Fable 5.1 需要 2.1.255+,
  # nix4vscode 数据里最高只有 2.1.252 时就卡住了。这里直接按 marketplace 的版本号钉,
  # 和 nix4vscode 的生成周期解耦(其余扩展照旧走 nix4vscode)。
  # 复用 nixpkgs 里现成的打包脚手架(autoPatchelfHook 负责 patch 那个 214MB 的
  # resources/native-binary/claude),只换 src 和版本号,drv 里没有编译,重建就是解压+patchelf。
  # 升级手续:改下面的 version,再跑这行拿新 hash:
  #   nix store prefetch-file --json --name anthropic-claude-code.vsix \
  #     "https://anthropic.gallery.vsassets.io/_apis/public/gallery/publisher/anthropic/extension/claude-code/<version>/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage?targetPlatform=linux-x64"
  # 查 marketplace 当前最新版本:
  #   curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
  #     -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=3.0-preview.1' \
  #     -d '{"filters":[{"criteria":[{"filterType":7,"value":"anthropic.claude-code"}],"pageSize":1}],"flags":950}' \
  #     | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['extensions'][0]['versions'][0]['version'])"
  claudeCodeVersion = "2.1.258";
  claudeCodeExt = pkgs.vscode-extensions.anthropic.claude-code.overrideAttrs (_: {
    version = claudeCodeVersion;
    src = pkgs.fetchurl {
      # 文件名必须以 .vsix 结尾:vscode-utils 的 unpackVsixSetupHook 靠扩展名触发解包
      name = "anthropic-claude-code.vsix";
      url = "https://anthropic.gallery.vsassets.io/_apis/public/gallery/publisher/anthropic/extension/claude-code/${claudeCodeVersion}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage?targetPlatform=linux-x64";
      hash = "sha256-eIJB3cp3HeD5DGcr/mp4kjkY/gMFp9oam8cGKeKSOMc=";
    };
  });

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
        # 和 vscodeBaseSettings 里那份重复:default 没引用 vscodeBaseSettings,
        # 而 git.autofetch 是 resource scope,不会从 default 继承到其他 profile。
        "git.autofetch" = true;
      };
    };
    profiles.nix = {
      extensions =
        pkgs.nix4vscode.forVscode [
          "jnoortheen.nix-ide"
          "natqe.reload"
          "kdl-org.kdl"
        ]
        ++ [ claudeCodeExt ];
      userSettings =
        vscodeBaseSettings
        // claudeCodeSettings
        // {
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
      extensions =
        pkgs.nix4vscode.forVscode [
          "ms-python.debugpy"
          "ms-python.vscode-pylance"
          "ms-python.python"
          "natqe.reload"
          "mk12.better-git-line-blame"
        ]
        ++ [ claudeCodeExt ];

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
      extensions =
        pkgs.nix4vscode.forVscode [
          "natqe.reload"
          "shd101wyy.markdown-preview-enhanced"
          "foam.foam-vscode"
        ]
        ++ [ claudeCodeExt ];
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
