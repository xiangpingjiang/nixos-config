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
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

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
  ];

}
