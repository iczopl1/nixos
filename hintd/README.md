# hintd

SUPER+D hints without Python. Two parts:

- `hintd` (Rust, always running, idle = blocked on its socket): reads AT-SPI on request, clicks through the wlr virtual pointer.
- `dotfiles/quickshell/bar/Hints.qml` + `BarTargets.qml`: the overlay, loaded by the Quickshell config linked to `~/.config/quickshell/` (`qs -c bar`). Black label, 2 px yellow outline.

## Socket `$XDG_RUNTIME_DIR/hintd.sock` (mode 0600, one request per connection)

| Request | Reply |
|---|---|
| `boxes live` | same as `boxes`, but no picture boxes (live mode) |
| `boxes` | first line: monitor name (empty line = no Mango state yet), then one `x y w h` per box, monitor-local |
| `click <monitor> <x> <y> <l\|m\|r\|h\|d>` | `ok`, `ok hold`, or `err <why>` (`x` = double click, `n` = move only, `h` = press and hold, `d` = drop) |
| `release` | `ok` (lets go of a held button) |
| `state` | `idle` or `hold` |

Env: `HINTD_SOCK` (must stay inside `$XDG_RUNTIME_DIR`), `HINTD_DEADLINE_MS` (per window, default 300), `HINTD_DEBUG=1` (prints step timings to stderr), `HINTD_GRIM=1`, `HINTD_NO_VISION=1`.

## Wiring (Mango)

    exec_once=setsid hintd >/dev/null 2>&1
    bind=SUPER,d,spawn,socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-hints-$WAYLAND_DISPLAY.sock
    # Escape / SUPER+c while holding: also let go
    bind=NONE,Escape,spawn_shell,printf 'release\n' | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock; mmsg dispatch setkeymode,default

The current tree already wires `Hints {}` into `dotfiles/quickshell/bar/shell.qml`, and
active key bindings are in `dotfiles/mango/config.conf`. No manual copy or merge
is needed. Optional bar targets can register with `BarTargets.add(mouseArea)` /
`BarTargets.remove(...)` and set `BarTargets.origin`, `screenName`, and `screenW`.
Runtime needs include `socat`, Mango's `mmsg`, `ydotool`, the `ydotool` user group,
AT-SPI2 and the Barlow font provided by `keyboard-mouse.nix`.

## Dev

    . ./env.sh                       # rustc + gcc from the Nix store
    cb build                         # cores 1-11 only; --profile bench for timing builds
    tests/hintd.sh                   # daemon checks on a scratch socket
    tests/grid9.sh                   # live: 6 apps on tag 9 in grid layout
    tests/soak.sh                    # leak check

    cb test --release                # picture analysis must give the same boxes as the first version (reference code kept in src/vision/tests.rs)
    HINTD_TEST_PPM=shot.ppm cb test --release -- --ignored --nocapture --test-threads=1   # same on a real screenshot, plus live capture tests (need the Wayland session)

## Picture boxes
Windows with no accessibility tree (terminals), apps that expose nothing, and empty lists get boxes found from a screenshot (edges, thickened, blobs). The screenshot is taken in the daemon through wlr-screencopy (`src/shot.rs`; monitor positions from xdg-output), about one compositor frame (12-14 ms) instead of starting `grim`. If the compositor refuses (or `HINTD_GRIM=1`), `grim` is used. `HINTD_NO_VISION=1` turns picture boxes off.

## Timing readout
`Hints.qml` serves a second socket, `$XDG_RUNTIME_DIR/qs-menu-hints-time-$WAYLAND_DISPLAY.sock`. Each connection flips a small "N ms · M boxes" text at the bottom right of the overlay (time from SUPER+D to boxes received). Bind it to any key:

    bind=SUPER+ALT,d,spawn,socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-hints-time-$WAYLAND_DISPLAY.sock

## Live mode (experimental)
Hints that refresh while the overlay is open: the overlay asks `boxes live` again 16 ms (one frame) after each request started (or at once if hintd was slower). Unmoved boxes keep their label, new boxes take free ones. The overlay is click-through (mouse and wheel reach the apps), keys still go to the hints, tag or window changes do not close it. Picture boxes are off (terminals only show the Alacritty whole-window hint). Esc, a pick, or the same bind again ends it. Measured: one `boxes live` round trip 35-55 ms with 68 boxes (includes starting `socat`).

    bind=SUPER+CTRL,d,spawn,socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-hints-live-$WAYLAND_DISPLAY.sock
