{
  inputs,
  pkgs,
  lib,
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
  ];
  xdg.desktopEntries.maestro-studio = {
    name = "Maestro Studio";
    exec = "${maestro-studio}/bin/maestro-studio";
    icon = "maestro-studio"; # 可选，没有图标也能显示
    categories = [ "Development" ];
  };
}
