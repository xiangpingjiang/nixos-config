{
  pkgs,
  ...
}:
{

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
    firefox = {
      enable = true;
    };
  };
}
