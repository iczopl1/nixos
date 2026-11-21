# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Quickshell (QML) config for a Wayland desktop on the Mango compositor. Hyprland is gone; do not target it. No build step, no tests, no linter. Edit a `.qml` file, then reload the bar and look at it.

Run configs by name: `qs -c <dir>`. Only `bar/` is live. It is a Waybar port that has absorbed the old standalone shells.
- `launcher/`, `lock/`, `glow/` are old single-file shells. Their jobs now live in `bar/` (`Menus.qml`, `Lock.qml`). Treat them as dead unless asked.
- `bar2/` is an older copy of the bar from 2 Nov. Do not edit it for bar changes.
- Git history starts on 2026-11-05. Before that, edits were snapshotted as `*.bak-*` files, now deleted. Use git for undo.

## Running and reloading the bar

WARNING: do not start the bar from a Claude shell with bare `qs -c bar`. The `claude` wrapper sets a bad `LD_LIBRARY_PATH` (alsa-lib needing glibc 2.43; system has 2.40). Anything started from it, such as apps opened from the launcher, dies with `GLIBC_2.43 not found`. Ask the user before starting or restarting it.

- Safe start: `~/.config/hypr/qs-launcher.sh` (strips alsa-lib from the path), SUPER+F11, or a fresh login.
- Test an app from a Claude shell as `env LD_LIBRARY_PATH=/etc/sane-libs <cmd>`.
- Check a running bar's env: `tr '\0' '\n' < /proc/<bar pid>/environ | grep LD_LIBRARY_PATH`.
- Toggle bar visibility: `qs -c bar ipc call bar toggle`.
- Open a menu fast (~7ms): `socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-<name>-$WAYLAND_DISPLAY.sock`. Slow fallback: `qs -c bar ipc call menus toggle <name>`. The launcher socket is `qs-launcher-$WAYLAND_DISPLAY.sock`.

## Architecture (`bar/`)

`shell.qml` is the root. One process hosts everything: a `Bar` per screen, plus `Menus`, `Hints`, `Lock`, `AudioRouter`, `Rotate`, `Notifications`. Several of these replaced separate processes (mako, rofi, bash watchers). So a crash or restart of the bar takes all of them down.

- **Bar visibility:** auto-hides while the focused workspace or tag is empty (`empty` in `shell.qml`). It reads Mango. `shell.qml` and `Bar.qml` still import `Quickshell.Hyprland`; that is leftover code from before, not a live path.
- **`Mango.qml`:** singleton. Runs `mmsg watch all-monitors` (one JSON per line) and exposes `monitors`, `focused`, `keymode`. Only active when `MANGO_INSTANCE_SIGNATURE` is set. Retries every 2s if the watcher exits.
- **`Theme.qml`:** singleton. Colors come from waybar's `colors.css` (written by `apply-wal-theme.py`), so a wal re-theme recolors the bar. It also holds the "flow" gradient. `Chip` colors itself from its x position (`Theme.flowAt`) and normalizes brightness (`Theme.normalize`). It also maps private-use icon glyphs to fonts through `fc-match`, because Qt does not do fontconfig fallback per glyph.
- **Bar modules:** `Chip` is the icon-first module (icon always shown, label slides out on hover or when pinned). `iconSvg: "name"` loads `icons/name.svg`, tinted by the foreground color. `ScriptChip` and `ScriptSeg` run a shell command on an interval and read JSON like `{"text":..,"class":..}`. `Seg` is the older text segment. Modules are declared inline in `Bar.qml` (about 800 lines). `shown: false` hides a module.
- **`Menus.qml` + `menus/`:** all menus (launcher, apps, clip, emoji, bluetooth, audio, keybinds, wallpaper, wallhaven) are built at startup in one overlay surface that stays mapped while hidden. Opening is a repaint, not a new surface. `MenuBox.qml` is the shared base. To add a menu, add it to both `names` and `menu()` in `Menus.qml`.
- **`Hints.qml`:** SUPER+D click-hint overlay. The `hintd` daemon does the accessibility reading and the click. In live mode it never takes the keyboard. Keys come from Mango keymode binds (`setKeymode`).
- **Keymap chip:** reads `Mango.keymode !== "clean"` and runs `~/.config/waybar/scripts/keymap-toggle.sh` on click. It is currently hidden (`shown: false` in `Bar.qml`). SUPER+TAB still toggles it.
- **Scripts:** most bar scripts (weather, keymap-toggle, nosleep-toggle, now-playing) live in `~/.config/waybar/scripts/` (`bar.wb` in `Bar.qml`). Only a few are in `bar/scripts/` (`sync-events.sh` long-polls Syncthing for the phone chip; `import-ics.py` and `export-ics.py` serve the calendar popup).

## Related files outside this repo

`~/.config/hypr/` is NOT a Hyprland config. It only holds old configs plus helper scripts that the bar still calls (`qs-launcher.sh`, `qs-lock.sh`, `spawn-alacritty.sh`, wallpaper and rofi scripts). Do not delete it. Mango binds and `mmsg` come from the Mango config.

## Effects merged in from the other (nixos-repo) dotfiles, 2026-11-19

`bar/Particles.qml` (+ `ParticleCanvas.qml`), `bar/WpmBorder.qml` (+ `EvtestReader.qml`),
`bar/Shortcuts.qml`, `bar/TypingGlow.qml` came from a second, now-deleted standalone
`shell.qml` at the root of this `quickshell/` tree (the pre-merge config for this host).
Nothing started that process any more after the `bar/` merge, so they were dead code —
moved into `bar/` and instantiated from `bar/shell.qml` so everything still runs as one
process. They do not depend on anything else that was root-level (they only used core
Quickshell modules), so the move was a straight copy + wire-up.

- **`Particles.qml`**: screen-wide particle themes (leaves/rain/snow/sparks/cursor). Since
  2026-11-19, more than one theme can be active at once — `activeThemes` is an array, not a
  single string, and `ParticleCanvas.qml` tags each particle with its own `theme` so several
  layers render simultaneously (shared budget: 80 particles total, not 80 per theme).
  Controlled by `effects particles <theme>` (exclusive, clears the rest) or
  `effects particles-<theme> on|off` (effects-ctl.sh, independent per theme) — both go
  through socket `qs-particles-set` (payload: comma-separated theme list, or empty for none).
  No keybind is wired to particles directly any more (SUPER+F6 now opens `effects edit` in a
  terminal instead, so the user can flip several `particles-*` lines by hand). The cycling
  socket `qs-particles` (`nextTheme()`) still exists for a future keybind; it now adds the
  next not-yet-active theme to the set each call, wrapping to empty once all five are on.
- **`WpmBorder.qml`**: recolors/thickens the focused window border by typing speed
  (evtest on every keyboard, via `EvtestReader.qml`). Three independent toggles
  (`colorEnabled`, `moveEnabled`, `countingEnabled`), persisted in `~/.config/wpm-effects`,
  controlled by `effects wpm-color|wpm-move|wpm-count` (sockets `qs-wpm-color|-move|-count`,
  toggle-on-connect — effects-ctl.sh reads the state file to turn a toggle into an exact
  on/off instead of blind-toggling).
- **`TypingGlow.qml`**: screen-edge glow driven by the same `WpmBorder.wpm`; gated by
  `WpmBorder.colorEnabled` (no separate switch).
- **`Shortcuts.qml`**: SUPER+H keybind cheatsheet overlay, socket `qs-shortcuts`.
- None of this is gated by `effects.conf`/AC power like `Fx.qml` below — these are
  controlled by the *other* repo's `effects-ctl.sh` (`~/.config/mango-effects.conf`,
  comment-to-disable) and battery-gated there (`battery-effects-monitor.sh`), which is a
  separate mechanism from `fxDir/effects.conf` used by `Fx.qml`. Don't conflate the two.

## power-fx (`/home/iczo/syshelp/power-fx/`)

power-fx now runs INSIDE the bar process: `bar/Fx.qml` (copy of power-fx's old `shell.qml`, loaded by `Fx {}` in `bar/shell.qml`). Read `/home/iczo/syshelp/power-fx/CLAUDE.md` first, but note: edit `bar/Fx.qml`, not `power-fx/shell.qml` (old file, kept as history). `ptrwatch`, `cursor-hide.sh` and `effects.conf` still live in the power-fx folder (`fxDir` in `Fx.qml`). It runs only on AC power and is idle on battery.

- If the user asks for an "AC only" effect or a "power effect", build it in `bar/Fx.qml` and add its on/off line to `/home/iczo/syshelp/power-fx/effects.conf` (a line without `#` is ON).
- Control: `/home/iczo/syshelp/power-fx/power-fx.sh list|toggle|on|off NAME|play|peak|pet ...` (these call `qs -c bar ipc call fx ...`). `start`/`stop` no longer launch a process; restart the bar to reload `Fx.qml`.
- The bar already reads `effects.conf` (`bar/Chip.qml`, `bar/Lock.qml`). Do the same for any bar effect that should obey it.
- Do not add effects that run on battery.

## Touchscreen gestures (`/home/iczo/syshelp/touch-gestures/`)

Touch gestures are NOT in the Mango config or the bar. Search here first for any touchscreen trigger.
- `touch-gestures.sh start|stop|restart|status` runs `tapd` (`tapd.cpp`), which reads the touchscreen and runs one command per gesture. The gesture table is the `CMD_*` exports in `run()` in the script. Edit the script, then `restart`.
- Name format: `CMD_SW_<fingers><dir>[_<edge>]`. dir is R L U D. Edge is L R T B (start edge).
- Overview: 3 fingers up = `mmsg dispatch toggleoverview`. A tap on a window in overview focuses it and leaves overview.
- 1 finger from left/right edge: previous/next tag. 1 finger from bottom edge up: launcher. 1 finger from top edge down: audio menu.
- 3 fingers from bottom edge up: on-screen keyboard. 3 fingers down: hide it. 3 fingers left/right: next/previous tag.
- 4 fingers: down = close window, up = clipboard menu, left/right = move window to next/previous tag.
- 5 fingers: left/right = focus, up = fullscreen.
- Taps: 3 = terminal, 4 = screenshot to clipboard, 5 = lock. Holds: 1 finger = right click, 2 fingers = toggle floating. Pinch resizes the window.
- Menu gestures use the same quickshell sockets as the Open-a-menu line above.
