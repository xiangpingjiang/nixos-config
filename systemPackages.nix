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

  #for sudo podman
  virtualisation.podman = {
    enable = true;
  };
  virtualisation.containers.policy = {
    default = [
      {
        type = "insecureAcceptAnything";
      }
    ];
  };

}
