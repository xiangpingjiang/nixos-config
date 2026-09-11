# NixOS System Configurations

This repository contains my NixOS system configurations. 
nixos + flake + home manager 


system update (configuration.nix only, does NOT apply home-manager):

    sudo nixos-rebuild  switch  --flake  -vv   

home-manager update (home-manager/ only):

    home-manager switch --flake . -b backup -v  

If both changed, run both.

## Switching location (netloc)

Outbound rules all route through one selector, `OUT`, and `claude` has its own.
`netloc` flips both and then verifies what actually happened:

    netloc cn          # back in China: outbound via the airport, Claude on a JP node
    netloc sg          # in Singapore: everything direct
    netloc             # status only, changes nothing
    netloc cn --quick  # skip the node health check (that step takes 1-2 min)
    netloc --fix-tun   # turn tun back on if it has dropped

Every step prints its own result and each failure is followed by what to do about
it; the script finishes all checks before exiting non-zero, so one run shows the
whole picture. What it verifies beyond the two switches: the selection actually
read back, the tun adapter exists, how many subscription nodes are reachable from
this network, a location-appropriate connectivity probe (`google` in China,
`polymarket` in Singapore — the latter only passes if DNS is not being sinkholed),
and that `claude` is not sitting on the wrong side.

`profile.store-selected` makes both choices survive a restart, so this is a
once-per-trip action, not a per-boot one.

If `netloc` is not on PATH yet (fresh checkout, no `home-manager switch`), the two
switches by hand:

    curl -X PUT -H 'Content-Type: application/json' -d '{"name":"MESL"}' \
      http://127.0.0.1:9097/proxies/OUT
    curl -X PUT -H 'Content-Type: application/json' -d '{"name":"MESL_Claude"}' \
      http://127.0.0.1:9097/proxies/claude

Why the script checks `claude` separately: the group is a `fallback` and its health
check does eventually correct a dead selection, but `store-selected` restores the
*stored* choice on startup, and convergence was observed to take anywhere from tens
of seconds to two or three minutes. Land in China with `DIRECT` stored and the
first requests leave over a Chinese IP, which is not a supported region — so run
`netloc cn` (or at least `netloc`) before starting a Claude session, not after.

tun must be on for any of this to matter: it is the only thing that hijacks system
DNS. With tun off, resolution falls back to the local resolver — in Singapore that
means the ISP's DNS sinkhole for blocked sites. Check with `ip -br addr | grep
Mihomo` (the `tun.enable` field in `/configs` is unreliable; it reported `false`
while the adapter was up and forwarding).

The adapter has twice disappeared on a running mihomo with nothing in the journal
to say why. `--fix-tun` PATCHes it back on (runtime only — the config already says
`enable: true`), but it is opt-in on purpose: silently repairing it every run would
hide how often it happens. Without the flag the script reports and leaves it.

## Falling back to a Chinese model (claude-ds)

`claude` is the official API on the company Max seat. `claude-ds` is the same
Claude Code pointed at DeepSeek's Anthropic-compatible endpoint. Two commands,
no mode to toggle:

    claude        # official
    claude-ds     # DeepSeek

The endpoint is fixed when the process starts. A running session cannot be moved
between the two, and `/model` only picks among the aliases of the endpoint that
session already uses — start a new session to change.

When Claude stops working from China, try in this order. Only the last step
gives up the Max seat:

1. `netloc` — is `claude` on `MESL_Claude` rather than `DIRECT`, and are the
   airport nodes reachable from this network? (`netloc cn` fixes the first and
   reports the second)
2. `journalctl -u mihomo -f` while retrying — a dial error names the entry IP it
   could not reach
3. `claude-ds`

First use needs a DeepSeek key — until then `claude-ds` refuses to start and
prints these steps:

    # get a key from https://platform.deepseek.com
    sops secrets/llm-keys.enc.yaml            # replace REPLACE_ME
    home-manager switch --flake . -b backup -v

Changing the key later needs the switch too: `.enc.yaml` is copied into the
store at eval time, so restarting `sops-nix` alone will not pick up a new value.

Features that need the first-party API go away on the fallback — Remote Control,
the Advisor, `/schedule`, Artifacts, MCP tool search. Hooks, skills, subagents
and checkpoints are local and keep working. CLAUDE.md has the full list and the
reasoning behind the wrapper.

The VS Code panel always uses the official API: the extension spawns its own
binary and never sees `--settings`. Use the terminal for the fallback.

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