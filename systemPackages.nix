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
    podman
    podman-compose
    go
    gcc
    python314
    nixfmt-rfc-style
    nil
    hugo
    chromium
    rclone
    rclone-ui


    amdgpu_top


    kdePackages.kdenlive
    lx-music-desktop

    nix-init
    aliyunpan
    telegram-desktop
    nixpkgs-review
    gh

    feishu
    wemeet



  ];

}
