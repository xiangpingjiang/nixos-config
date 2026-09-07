# NixOS System Configurations

This repository contains my NixOS system configurations. 
nixos + flake + home manager 


system update (configuration.nix only, does NOT apply home-manager):

    sudo nixos-rebuild  switch  --flake  -vv   

home-manager update (home-manager/ only):

    home-manager switch --flake . -b backup -v  

If both changed, run both.

## Active Claude Code sessions (cc-sessions)

`cc-sessions` lists every live Claude Code session on this machine, grouped by
VS Code window, with each session's title and state. `cc-sessions --watch` is
what the zellij `cc` tab runs; new zellij sessions get that tab automatically
(`home-manager/develop/zellij/dev.kdl`).

Liveness comes from processes, not from any bookkeeping: a session in the VS Code
extension is a direct child of that window's extension host. Titles and state are
read from the session transcripts under `~/.claude/projects/`. See CLAUDE.md for
how processes are matched to transcripts.

Hook changes only take effect in newly started Claude Code sessions.

## Troubleshooting

Panel moved to the built-in screen / wrong primary display (KWin saved duplicate
output priorities after monitor hotplug, lid open/close, or Feishu screen-share
virtual outputs). Use the uuid, not the connector name — the name itself drifts
between reboots (DP-2 -> DP-1), the uuid is stable:

    # uuid of the current external monitor; re-check with `kscreen-doctor -o` after changing monitors
    kscreen-doctor output.73ad35c6-a068-4f37-a2c0-99a1fedd7060.priority.1 output.eDP-1.priority.2

Check with `kscreen-doctor -o` — each output's priority should be unique.