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
      sha256 = "04hiw3xy6ahhkgz12269bs555m18hqv44r3ydybhr9ngyzplkdll";
    };
  };
in
{

  home.username = "xpj";
  home.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./plasma.nix
    ./rclone.nix
    ./secrets.nix
    ./vscode.nix
    inputs.nix-openclaw.homeManagerModules.openclaw
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
        command = "/etc/profiles/per-user/xpj/bin/zsh";
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

    opencode = {
      enable = true;
      # settings = {
      #   provider = {
      #     openrouter = {
      #       models = {
      #         "anthropic/claude-3.5-sonnet" = {
      #           name = "Claude 3.5 Sonnet";
      #         };
      #         "openai/gpt-4o" = {
      #           name = "GPT-4o";
      #         };
      #         "google/gemini-pro" = {
      #           name = "Gemini Pro";
      #         };
      #       };
      #     };
      #   };
      # };
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
    pkgs-latest.claude-code
    claude-code-router
    scrcpy
    android-tools
    kdePackages.krfb

    devenv
    direnv
    dig
    dbeaver-bin

    maestro-studio
    pkgs-latest.maestro

  ];
  xdg.desktopEntries.maestro-studio = {
    name = "Maestro Studio";
    exec = "${maestro-studio}/bin/maestro-studio";
    icon = "maestro-studio";  # 可选，没有图标也能显示
    categories = [ "Development" ];
  };
}
