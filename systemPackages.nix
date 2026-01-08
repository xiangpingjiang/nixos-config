{
  pkgs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    git
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
    clash-verge-rev
    chromium
    vscode
    zsh
    rclone
    rclone-ui

    ghostty


  ];

}
