#!/usr/bin/env bash
# Duplicate the active alacritty: same live colors (via IPC) and same working directory.
# Normally run by alacritty itself (Super+Shift+W in alacritty.toml): alacritty sets
# ALACRITTY_SOCKET/ALACRITTY_WINDOW_ID for this window and cwd to its shell's cwd,
# which also works for windows of the shared daemon (one pid for all windows).
# Called from the compositor instead, it finds the window by pid (standalone only).
if [ -n "${ALACRITTY_WINDOW_ID:-}" ] && [ -S "${ALACRITTY_SOCKET:-}" ]; then
  sock=$ALACRITTY_SOCKET
  win=(-w "$ALACRITTY_WINDOW_ID")
  cwd=$PWD
else
  if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
    read -r class pid < <(mmsg get focusing-client | jq -r '"\(.appid) \(.pid)"')
  else
    read -r class pid < <(hyprctl activewindow -j | jq -r '"\(.class) \(.pid)"')
  fi
  [ "$class" = Alacritty ] || exit 0
  sock="$XDG_RUNTIME_DIR/Alacritty-wayland-1-$pid.sock"
  win=()
  shell=$(pgrep -P "$pid" | head -1)
  cwd=$(readlink "/proc/${shell:-$pid}/cwd" || echo "$HOME")
fi

# Same 19-color order spawn-alacritty.sh uses: bg fg bg_raw color0..color15
palette=$(alacritty msg --socket "$sock" get-config "${win[@]}" | jq -r '
  .colors | [.primary.background, .primary.foreground, (.cursor.foreground // .primary.background),
    (.normal | .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white),
    (.bright | .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white)] | join(" ")')

ALACRITTY_PALETTE="$palette" exec "$HOME/.config/hypr/spawn-alacritty.sh" --working-directory "$cwd"
