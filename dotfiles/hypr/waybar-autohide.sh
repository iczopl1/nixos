#!/usr/bin/env bash
# Kills waybar when the focused workspace becomes empty, respawns it when it stops being empty.
# Acts only on that change, so a bar summoned by hand (F11) stays up until the state flips.
set -uo pipefail

DISABLED_FILE="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/waybar-disabled"
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
START="$HOME/.config/waybar/scripts/start-waybar.sh"
BAR='(^|/)waybar( |$)'
PENDING='waybar/scripts/start-waybar'   # a spawn already in flight (python theme step)
# module scripts detach from waybar at spawn, so they must be matched by name, not parent
MODULES="^([^ ]*/)?(bash|sh|python3?) $HOME/.config/waybar/scripts/"

was=""

sync() {
  empty=$(hyprctl activeworkspace -j | jq -r '.windows == 0')
  [ "$empty" = "$was" ] && return                    # only act on a change
  was=$empty
  rm -f "$DISABLED_FILE"                             # a state change ends any F11 override
  up=$(pgrep -f "$BAR|$PENDING" | head -n1)

  if [ "$empty" = true ] && [ -n "$up" ]; then
    pkill -f "$BAR"
    pkill -f "$MODULES"                              # module scripts outlive the bar
  elif [ "$empty" = false ] && [ -z "$up" ]; then
    setsid nohup "$START" >/dev/null 2>&1 &
  fi
}

sync
# only events that can change the window count of the focused workspace
socat -U - "UNIX-CONNECT:$SOCKET" |
  grep --line-buffered -E '^(workspace|focusedmon|openwindow|closewindow|movewindow)' |
  while read -r _; do
  while read -r -t 0.15 _; do :; done                # debounce: drain the event burst
  sync
done
