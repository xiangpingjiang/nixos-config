{
  inputs,
  pkgs,
  ...
}:

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
        command = "/run/current-system/sw/bin/zsh";
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
      package = inputs.nixpkgs-chromium-144.legacyPackages.x86_64-linux.chromium;
      commandLineArgs = [
        # https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland#KDE_Plasma
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        "--user-data-dir=$HOME/.config/chromium-compat" # 和最新版本的不兼容，这条命令数据隔离
      ];
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
  ];

}
