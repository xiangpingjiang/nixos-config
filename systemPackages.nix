{
  pkgs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    unzip
    localsend
    keepassxc
    fastfetch
    podman-compose
    go
    gcc
    python314
    nixfmt
    nil
    hugo
    restic # to control snapshots


    amdgpu_top


    # kdePackages.kdenlive
    lx-music-desktop

    nix-init
    aliyunpan
    telegram-desktop
    nixpkgs-review
    gh

    feishu

    wechat
    insomnia
    devenv
    (callPackage "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/pkgs/agenix.nix" {})



  ];

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    kate
    konsole
  ];

  

  # virtualisation.waydroid.enable = true;
  # virtualisation.waydroid.package = pkgs.waydroid-nftables;
  # networking.nftables.enable = true;


}
