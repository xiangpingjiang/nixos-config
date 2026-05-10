{
  pkgs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [

    podman-compose
    go
    gcc
    python314
    nixfmt
    nil
    hugo

    # kdePackages.kdenlive
    lx-music-desktop

    nix-init
    age # 用来查看 mihomo config 的 diff
    jdk8

  ];

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    qrca
  ];

  # virtualisation.waydroid.enable = true;
  # virtualisation.waydroid.package = pkgs.waydroid-nftables;
  # networking.nftables.enable = true;

}
