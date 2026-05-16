{
  inputs,
  pkgs,
  lib,
  ...
}:

let

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
  home.homeDirectory = "/home/xpj";
  home.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.nix4vscode.overlays.default ];
  imports = [
    ./plasma.nix
    ./rclone.nix
    ./secrets.nix
    ./programs.nix
    ./develop/vscode.nix
    ./develop/claude-code.nix
    ./develop/codex.nix
    ./develop/opencode.nix
    ./develop/deepseek-tui.nix
    # inputs.nix-openclaw.homeManagerModules.openclaw
  ];
  nix.package = lib.mkDefault pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # backupFileExtension 的位置没有问题
  # 问题出在别处 nix-openclaw 这个第三方 home-manager 模块
  # home.file.".openclaw/openclaw.json".force = true;

  # services = {
  #   podman = {
  #     enable = true;
  #     settings.policy = {
  #       default = [ { type = "insecureAcceptAnything"; } ];
  #     };
  #   };
  # };

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

    maestro-studio
    maestro
    mitmproxy
    openssl

    maven
    jdt-language-server

    go-jsonnet
    jsonnet-bundler

    telegram-desktop
    nixpkgs-review
    gh

    feishu
    insomnia

    restic # 需要cli unlock 或者，远端恢复
    wget
    unzip
    localsend
    keepassxc
    fastfetch
    unrar-free

    (inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default) # 单独执行 hm 的更新

    beekeeper-studio
    basedpyright
    nodejs
    inputs.serena.packages.${pkgs.stdenv.hostPlatform.system}.serena
  ];
  xdg.desktopEntries.maestro-studio = {
    name = "Maestro Studio";
    exec = "${maestro-studio}/bin/maestro-studio";
    icon = "maestro-studio"; # 可选，没有图标也能显示
    categories = [ "Development" ];
  };
}
