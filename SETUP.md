# Setup (for an AI agent)

NixOS 25.11 modules, classic (no flakes, no home-manager). Personal values are anonymized.
Merged: nixos-selected (base) + old flake config `nixos` (without Hyprland).

## Install (system)
1. Copy the WHOLE folder (all `*.nix`, `*.patch`, `hintd/`, `quickshell/`, `dotfiles/`) into `/etc/nixos/`.
   `configuration.nix` already imports every module (merged config, see README.md).
2. Check `hardware-configuration.nix` (taken from the old laptop host); regenerate with
   `nixos-generate-config --show-hardware-config` if the disks differ.
3. `nixos-rebuild build`, then `nixos-rebuild switch`. Needs network (unstable is fetched unpinned).
4. Dotfiles are symlinked by `dotfiles.nix` (systemd user tmpfiles) on next login; existing
   `~/.config/{nvim,rofi,cava,waybar}` are NOT overwritten - move them away first.

## Dependencies
- `unstable.nix` must be imported: it provides the `unstable` arg used by mango.nix and keyboard-mouse.nix.
- `keyboard-mouse.nix` builds `hintd/` (Rust) and needs `wl-kbptr-vimium.patch` beside it.
- `mango.nix` needs `mango-tag-slidefade.patch` beside it.
- `crafts.nix`, `ros2.nix`, `tailnet-b.nix` are self-contained.
- `clev.nix` is included but NOT buildable: its source (`./hintdrive`) is not shipped. Do not import it unless that source is provided.

## hintd (SUPER+D hints, SUPER+CTRL+D live hints)
Chain: mango bind -> quickshell overlay (`Hints.qml`) socket -> `hintd` daemon (reads AT-SPI, clicks via wlr virtual pointer).
1. Copy `quickshell/bar/*` into the quickshell config dir of the running bar (here `~/.config/quickshell/bar/`).
2. In that bar's `shell.qml`, add `Hints {}` inside the root item. `Mango.qml` and `BarTargets.qml` are singletons; skip `Mango.qml` if the bar already has one.
3. Optional: bar items register with `BarTargets.add(mouseArea)` / `BarTargets.remove(...)` and set `BarTargets.origin`, `screenName`, `screenW` so the overlay also hints bar buttons.
4. Merge `mango-hintd.conf` into `~/.config/mango/config.conf` (comments say where each block goes). Check: `mango -c ~/.config/mango/config.conf -p`.
5. Runtime needs: `socat`, `mmsg` (mango), `ydotool` (user in `ydotool` group), Barlow font (installed by keyboard-mouse.nix).
6. Log out and in. Details and socket protocol: `hintd/README.md`.

## Fill in
- `tailnet-b.nix`: `bSuffix` (`tailnet-b.example.ts.net`) -> real MagicDNS suffix; `bOctet`, `bHosts` -> real tailnet B addresses; `"laptop"` -> this host's name in tailnet B.

## After switch
- tailnet B: `tailscale --socket=/run/tailscale-b/tailscaled.sock up`. Expects normal Tailscale (tailnet A) on `tailscale0` too.
- ros2: opens UDP 7400-7500 on all interfaces (DDS discovery).
- keyboard-mouse.nix wraps signal-desktop and ferdium with an accessibility flag; remove the two `withA11y` lines if unwanted.
