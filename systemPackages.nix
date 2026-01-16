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
    # clash-verge-rev
    chromium
    vscode
    rclone
    rclone-ui

    ghostty

    amdgpu_top


    kdePackages.kdenlive


  ];

}
