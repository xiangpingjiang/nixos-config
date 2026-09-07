{
  pkgs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  environment.systemPackages = with pkgs; [

    podman-compose

    age # 用来查看 mihomo config 的 diff
    jdk8

  ];

  #for sudo podman
  virtualisation.podman = {
    enable = true;
  };
}
