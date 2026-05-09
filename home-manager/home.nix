{
  inputs,
  pkgs,
  ...
}:

let
  # 为 nixpkgs-latest 创建一个允许 unfree 包的实例
  pkgs-latest = import inputs.nixpkgs-latest {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  maestro-studio = pkgs.appimageTools.wrapType2 {
    pname = "maestro-studio";
    version = "latest";
    src = pkgs.fetchurl {
      url = "https://studio.maestro.dev/MaestroStudio.AppImage";
      sha256 = "sha256-8S3tqdykR11a1feOlNCiSqu0SCEcnkjJU45byIEymEA=";
    };
  };
in
{

  home.username = "xpj";
  home.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.nix4vscode.overlays.default ];
  imports = [
    ./plasma.nix
    ./rclone.nix
    ./secrets.nix
    ./vscode.nix
    ./claude-code.nix
    ./opencode.nix
    # inputs.nix-openclaw.homeManagerModules.openclaw
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # backupFileExtension 的位置没有问题
  # 问题出在别处 nix-openclaw 这个第三方 home-manager 模块
  # home.file.".openclaw/openclaw.json".force = true;

  programs = {
    ghostty = {
      enable = true;
      settings = {
        # shell-integration = zsh;
        command = "${pkgs.zsh}/bin/zsh";
        theme = "Tomorrow Night Eighties";
        # font-size = 10;
        # keybind = [
        #   "ctrl+h=goto_split:left"
        #   "ctrl+l=goto_split:right"
        # ];
      };
    };

    # openclaw = {
    #   enable = true;
    #   package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openclaw;
    #   config = {
    #     gateway = {
    #       mode = "local";
    #       auth = {
    #         token = "<gatewayToken>"; # or set OPENCLAW_GATEWAY_TOKEN
    #       };
    #     };
    #     channels.telegram = {
    #       tokenFile = config.age.secrets.openclaw_channel_telegram.path;
    #       allowFrom = [ 6275695642 ];
    #     };

    #     env.vars = {
    #       ZAI_API_KEY = config.age.secrets.zai_api_key.path;
    #     };

    #     agents.defaults = {
    #       model = {
    #         primary = "zai/glm-4.7-flash";
    #         fallbacks = [
    #           "zai/glm-4.7-flash"
    #           "zai/glm-4.6-flash"

    #         ];
    #       };
    #       models = {
    #         "zai/glm-4.7-flash" = {
    #           alias = "GLM-4.7-Flash";
    #         };
    #       };
    #     };
    #   };
    # };

    obsidian = {
      enable = true;
    };
    chromium = {
      enable = true;
      # package = inputs.nixpkgs-chromium-144.legacyPackages.x86_64-linux.chromium;
      commandLineArgs = [
        # https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland#KDE_Plasma
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        # "--user-data-dir=$HOME/.config/chromium-compat" # 和最新版本的不兼容，这条命令数据隔离
      ];
    };

    # 配置使用 zsh
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        theme = "";
        plugins = [
          "git"
          "dirhistory"
          "history"
          "direnv"
        ];
      };
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
    };

    java = {
      enable = true;
      package = pkgs.jdk21;
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

  home.packages = with pkgs; [
    gitleaks
    kubectl
    kind
    claude-code-router
    scrcpy
    android-tools
    kdePackages.krfb
    kdePackages.krdc

    devenv
    direnv
    dig
    dbeaver-bin

    maestro-studio
    pkgs-latest.maestro
    mitmproxy
    openssl
    # (nomachine-client.overrideAttrs (old: {
    #   src = pkgs.fetchurl {
    #     url = "https://download.nomachine.com/download/9.4/Linux/nomachine_9.4.14_1_x86_64.tar.gz";
    #     hash = "sha256-tLL8l/UgTiVzGs+mwJeRUlVA8lH72JVogBOEpaSr2AY=";
    #   };
    # }))
    maven
    jdt-language-server

    go-jsonnet
    jsonnet-bundler
  ];
  xdg.desktopEntries.maestro-studio = {
    name = "Maestro Studio";
    exec = "${maestro-studio}/bin/maestro-studio";
    icon = "maestro-studio"; # 可选，没有图标也能显示
    categories = [ "Development" ];
  };
}
