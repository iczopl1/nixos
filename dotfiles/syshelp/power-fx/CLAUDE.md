# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

power-fx is a single quickshell overlay for the mango compositor (NixOS, Wayland). It draws cursor effects (trail, click rings) and desktop/tile effects (focus, swap, close, notify, plug-in...). It runs only on AC power and must be fully idle on battery. There is no build system, test suite or linter.

## Commands

```
./power-fx.sh start|restart     # stop old copy, rebuild ptrwatch if ptrwatch.cpp is newer, launch shell.qml
./power-fx.sh stop|status
./power-fx.sh list              # effects.conf switches with ON/off
./power-fx.sh toggle|on|off NAME
./power-fx.sh play [0-5] | peak N | wow KIND | urgent SECS | move DIGITS   # IPC previews (target `fx`)
quickshell -p shell.qml ipc show                       # check the shell loaded (hot reload is unreliable: restart instead)
g++ -O2 -std=c++17 -Wall -Wextra -o ptrwatch ptrwatch.cpp   # manual ptrwatch build (power-fx.sh does this)
```

- Wrap daemon/stream commands (`mmsg watch ...`, `dbus-monitor`, `quickshell ... ipc`) in `timeout`.
- Never start, nest, restart or kill the compositor/session; never edit `/etc`.
- `power-fx.sh` runs everything in one process group (pid in `$XDG_RUNTIME_DIR/power-fx.pid`) so `stop` leaves no orphans. Keep it that way: one quickshell process, everything merged into `shell.qml`.
- Languages: C++/Rust and QML/bash only, no Python.
- Before editing `shell.qml` or `ptrwatch.cpp`, copy to `*.bak-pre-<topic>` (the existing convention; `.bak*` files are history, the unsuffixed file is live).

## Architecture

Data flow: `ptrwatch` (C++, event-driven) and `mmsg watch ...` streams feed `shell.qml`, which keeps state and draws on one click-through `PanelWindow` per screen (Canvas 2D, empty input mask).

- `ptrwatch.cpp`: reads the pointer and input devices and prints one line per event to stdout: `c`/`cr`/`cm` click (left/right/middle), `d`/`u` button down/up, `s DX DY` scroll, `k`/`K` key seen 70 ms/220 ms ago, plus the cursor position as JSON. It spawns `mmsg watch all-devices` and only looks at device kind, never key codes. While the `ydotoold virtual device` is active (keyboard cursor mode, SUPER+c) it polls the position.
- `shell.qml` (one file, ~2200 lines):
  - Sources: ptrwatch `Process`/`SplitParser`; `mmsg watch all-clients`, `all-monitors`, `keymode`; `FileView`s on `/sys/class/power_supply/AC/online` and `ucsi-source-psy-*/online` (`onAC = acOnline || usbOnline`); `dbus-monitor` on `Notify` (the notification daemon is the user's bar, `qs -c bar`); udev for plug events.
  - Cursor layer: `trail` canvas (points, sparkles, ghost layer, click `rips`).
  - Tile/desktop layer: `fxList` holds timed effects `{kind, t, dur, x, y, w, h, mon, ...}`. Create them with `fxAdd(e)` (all go through it), size them with `fxBounds`/`fxRetarget`, expire with `fxEnd`/`fxAlive`, draw them in `drawFx(ctx, e, now, scr)` by `e.kind`. `mine()`/`animating()`/`onlyBreathing()` decide whether the paint tick runs (idle must cost nothing).
  - `moveFx` digits choose which swap effects run on real moves: 2 = landing flash, 6 = edge spray (focused tile only).
  - IPC `fx` handler (`play`, `peak`, `move`, `urgent`, `wow`) is for previews and tests.
- Hidden cursor: `cursor-hide.sh on|off` sets `cursor_theme=invisible` in `~/.config/mango/config.conf` and reloads. `power-fx.sh stop` always calls `off`. If the cursor stays hidden: `./cursor-hide.sh off`.

## Effect switches

`effects.conf` is the table of contents: a line starting with an effect name is ON, `#` in front turns it OFF. Order does not matter. It is watched (`FileView`, applies within a second); an unreadable file means all on. To add a switch:
1. Add a line to `effects.conf` (lowercase name + `# description`).
2. Gate the code with `root.fxOn("name")`. For `fxAdd` effects, map the `e.kind` to the name in `fxGroup` instead.

The bar ripples (`barripple`, `volripple`) are read from the same file by `~/.config/quickshell/bar/Chip.qml`, not by `shell.qml`.

## Gotchas

- mango streams no geometry during keyboard resize (`resizewin`), so the resize glow is fed by the `K` key snapshot and is unverified.
- Mango needs positive monitor coordinates (XWayland click bug).
- Unused or disabled code kept on purpose: `fxHop`, `fxGaps`, `fxWash`, `fxLevel` (+ `volProc`, `briFile`), `fxClose`. The header comment of `shell.qml` ("via poll.sh") is stale.
- The system packages (`click-input-access.nix`, ydotool/input access) are staged in `~/syshelp` for the user to copy into `/etc/nixos`; do not write to `/etc`.
