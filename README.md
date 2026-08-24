# NixOS System Configurations

This repository contains my NixOS system configurations. 
nixos + flake + home manager 


system update (configuration.nix only, does NOT apply home-manager):

    sudo nixos-rebuild  switch  --flake  -vv   

home-manager update (home-manager/ only):

    home-manager switch --flake . -b backup -v  

If both changed, run both.

## Claude Code Agent Monitor (CCAM)

Local dashboard at <http://localhost:4820>, kept running by the
`ccam-dashboard` user service. Its hooks are declared in
`home-manager/develop/claude-code.nix`, but the source tree lives outside the
store at `~/.local/share/ccam`, so upgrades do NOT go through
`home-manager switch`:

    cd ~/.local/share/ccam && git pull && npm install && npm run build
    systemctl --user restart ccam-dashboard

Hook changes only take effect in newly started Claude Code sessions.

## Troubleshooting

Panel moved to the built-in screen / wrong primary display (KWin saved duplicate
output priorities after monitor hotplug, lid open/close, or Feishu screen-share
virtual outputs). Use the uuid, not the connector name — the name itself drifts
between reboots (DP-2 -> DP-1), the uuid is stable:

    # uuid of the current external monitor; re-check with `kscreen-doctor -o` after changing monitors
    kscreen-doctor output.73ad35c6-a068-4f37-a2c0-99a1fedd7060.priority.1 output.eDP-1.priority.2

Check with `kscreen-doctor -o` — each output's priority should be unique.