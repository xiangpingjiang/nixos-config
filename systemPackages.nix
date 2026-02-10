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
    chromium
    rclone
    rclone-ui


    amdgpu_top


    # kdePackages.kdenlive
    lx-music-desktop

    nix-init
    aliyunpan
    telegram-desktop
    nixpkgs-review
    gh

    feishu
    wemeet

    wechat
    insomnia
    devenv


  ];

}
