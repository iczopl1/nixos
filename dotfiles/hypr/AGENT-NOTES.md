This directory is the user's live Hyprland config on plain NixOS.

User:
- Prefers pragmatic, minimal, testable changes.
- Touchscreen support is a priority.
- Wants custom gestures and a usable on-screen keyboard.
- Does not want flakes or Home Manager for this desktop setup.

General structure:
- `hyprland.conf` is the main config.
- `keybinds.conf` is sourced from `hyprland.conf`.
- `touchscreen.conf` is not statically sourced from `hyprland.conf`.
- `load-touchscreen.sh` dynamically loads `hyprgrass` and applies `touchscreen.conf`.

Important history:
- Earlier static plugin/source attempts bricked Hyprland startup.
- Keep the current dynamic `hyprgrass` flow unless you verify a safer parser path.
- `maliit` was tried and abandoned after plugin-path and GSettings/runtime failures.
- `squeekboard` was tried and abandoned after layout/session-integration issues.
- Current OSK path is `wvkbd`.

Current `hyprland.conf` state:
- Monitors:
  - default monitor line: `monitor=,preferred,auto,1`
  - `eDP-1`: `1920x1080` at `0x0`, scale `1`
  - `HDMI-A-1`: `3840x2160` at `1920x-1080`, scale `1.5`
- Program variables:
  - `$terminal = alacritty`
  - `$fileManager = thunar .`
  - `$menu = rofi -show drun -theme ~/.config/rofi/rofi.rosi`
  - `$ss = grim -g "$(slurp)" - | wl-copy`
  - `$lock = hyprlock`
  - `$web = librewolf`
  - `$clip = cliphist list | rofi -dmenu -i -p clipboard -theme ~/.config/rofi/rofi2.rosi | cliphist decode | wl-copy`
  - `$scriber = pkill -SIGUSR1 wayscriber`
- Autostart:
  - `kdeconnectd`
  - `iio-hyprland eDP-1`
  - `hyprctl setcursor Adwaita 96`
  - `swww-daemon`
  - `mako`
  - `switch-random-wallpaper.sh`
  - `rotate-random-wallpaper.sh`
  - `launch-cava-bg.sh`
  - `waybar`
  - `wl-paste --type text --watch cliphist store &`
  - `wl-paste --type image --watch cliphist store &`
  - `hypridle`
  - `bgm-power-monitor.sh`
  - `sleep 3; wayscriber --daemon`
  - `exec = ~/.config/hypr/load-touchscreen.sh`
- Environment:
  - `XCURSOR_SIZE=96`
  - `XCURSOR_THEME=Adwaita`
  - `QT_QPA_PLATFORMTHEME=qt6ct`
  - `GTK_THEME=adw-gtk3-dark`
  - also runs `gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"`
- General look/behavior:
  - `gaps_in = 7`
  - `gaps_out = 14`
  - `border_size = 2`
  - `resize_on_border = false`
  - `allow_tearing = true`
  - `layout = dwindle`
  - decoration rounding `10`
  - inactive dim enabled with strength `.1`
  - active opacity `.97`
  - inactive opacity `.87`
  - blur disabled
  - shadows disabled
  - animations enabled
  - `dwindle.preserve_split = true`
  - `misc.force_default_wallpaper = 0`
  - `misc.disable_hyprland_logo = true`
- Input:
  - `kb_layout = pl`
  - `follow_mouse = 1`
  - `sensitivity = 0`
  - touchpad natural scroll enabled
- The old native line `gesture = 3, horizontal, workspace` is commented out.
- `source = ~/.config/hypr/keybinds.conf`
- `windowrule = suppressevent maximize, class:.*`

Current `keybinds.conf` state:
- Main modifier: `SUPER`
- Basic/app binds:
  - `SUPER+Q` kill active
  - `SUPER+M` lock
  - `SUPER+E` file manager
  - `SUPER+W` terminal
  - `SUPER+X` browser
  - `SUPER_L` menu via `bindir`
  - `SUPER+SHIFT+S` screenshot
  - `SUPER+V` clipboard picker
  - `SUPER+F3` wayscriber signal
  - `SUPER+F10` switch random wallpaper
  - `SUPER+F11` toggle waybar
  - `SUPER+F12` toggle bgm power monitor
  - `SUPER+O` toggle `wvkbd`
  - `SUPER+INSERT` skip bgm track
- Window/layout binds:
  - `SUPER+T` toggle floating
  - `SUPER+P` pseudo
  - `SUPER+U` toggle split
  - `SUPER+F` fullscreen
- Focus movement:
  - `SUPER+J/L/I/K` move focus left/right/up/down
- Resize:
  - `SUPER+CTRL+L/J/I/K` resize active
- Move window:
  - `SUPER+SHIFT+L/J/K/I` move window
- Workspaces:
  - `SUPER+1..0` to workspaces `1..10`
  - `SUPER+A` previous workspace
  - `SUPER+S` next workspace
  - `SUPER+SHIFT+1..0` move active window to workspace `1..10`
- Mouse:
  - `SUPER + mouse:272` move window
  - `SUPER + mouse:273` resize window
- Multimedia:
  - volume up/down, mute, mic mute
  - brightness up/down
- Cleanup submap:
  - `SUPER+Delete` enters `clean`, then immediately reset
- Zoom:
  - `SUPER+F2` increase cursor zoom via `hyprctl` + `jq`
  - `SUPER+F1` decrease cursor zoom, floored at `1`
- Lid:
  - `switch:on:Lid Switch` runs `hyprlock`

Current `touchscreen.conf` state:
- `gestures.workspace_swipe = true`
- `gestures.workspace_swipe_cancel_ratio = 0.08`
- `plugin.touch_gestures`:
  - `sensitivity = 5.0`
  - `workspace_swipe_fingers = 2`
  - `long_press_delay = 250`
  - `resize_on_border_long_press = true`
  - `edge_margin = 64`
- Edge gestures:
  - bottom edge swipe up: `exec, $menu`
  - top edge swipe down: `exec, $lock`
  - top edge swipe left: `exec, $ss`
  - bottom edge swipe right: `exec, $clip`
  - left edge swipe right: `exec, ydotool key 56:1 105:1 105:0 56:0`
  - right edge swipe left: `exec, ydotool key 56:1 105:1 105:0 56:0`
- Tap/swipe gestures:
  - `tap:3`: terminal
  - `swipe:4:d`: toggle floating
  - `swipe:4:u`: fullscreen
  - `swipe:3:d`: kill active
  - `swipe:3:u`: run `toggle-wvkbd.sh`
- Long press:
  - `longpress:2`: move window
  - `longpress:3`: resize window

Current `load-touchscreen.sh` state:
- `PLUGIN_PATH="/run/current-system/sw/lib/libhyprgrass.so"`
- `CONFIG_PATH="$HOME/.config/hypr/touchscreen.conf"`
- If `hyprgrass` is not in `hyprctl plugin list`, it loads the plugin.
- Then it runs `hyprctl keyword source "$CONFIG_PATH"`.
- This script is the current safe path for applying touchscreen gestures.

Current `wvkbd.conf` state:
- `WV_KBD_BIN="wvkbd-mobintl"`
- `WV_KBD_HEIGHT=420`
- `WV_KBD_LANDSCAPE_HEIGHT=280`
- `WV_KBD_FONT="DejaVu Sans 26"`
- `WV_KBD_RADIUS=14`
- `WV_KBD_LAYERS="full,special,emoji"`
- `WV_KBD_LANDSCAPE_LAYERS="landscape,landscapespecial"`

Current `toggle-wvkbd.sh` state:
- Sources `~/.config/hypr/wvkbd.conf`
- If `wvkbd-mobintl` is already running, sends `pkill -RTMIN -x "$WV_KBD_BIN"` and exits
- Otherwise execs `wvkbd-mobintl` with:
  - `-H "$WV_KBD_HEIGHT"`
  - `-L "$WV_KBD_LANDSCAPE_HEIGHT"`
  - `-R "$WV_KBD_RADIUS"`
  - `--fn "$WV_KBD_FONT"`
  - `-l "$WV_KBD_LAYERS"`
  - `--landscape-layers "$WV_KBD_LANDSCAPE_LAYERS"`

Known caveats:
- `wvkbd` is manual-toggle only. It does not auto-open on text focus.
- `ydotoold` was confirmed running as a system service on this machine.
- `YDOTOOL_SOCKET` was not exported in the session when checked.
- Because of that, the current left/right edge "back" gestures in `touchscreen.conf` may fail until either:
  - Hyprland exports `env = YDOTOOL_SOCKET,/run/ydotoold/socket`, or
  - the gesture commands are changed to inline `env YDOTOOL_SOCKET=/run/ydotoold/socket ydotool ...`
- If "back" gestures do not work, inspect that first before changing the gesture logic.

Files worth checking before future edits:
- `hyprland.conf`
- `keybinds.conf`
- `touchscreen.conf`
- `load-touchscreen.sh`
- `wvkbd.conf`
- `toggle-wvkbd.sh`

Editing guidance for future agents:
- Be conservative. This is a live user config.
- Prefer small, testable changes.
- Avoid reintroducing static `touchscreen.conf` sourcing or static plugin config unless deliberately reworked.
- Preserve the current dynamic `hyprgrass` loader path unless the user explicitly wants a different approach.
