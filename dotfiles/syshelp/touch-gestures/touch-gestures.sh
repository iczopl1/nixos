#!/usr/bin/env bash
# Touchscreen gestures for mango (tapd does everything: swipes, taps, long-press, pinch, window drag).
#   touch-gestures.sh start|stop|restart|status
# Both programs run in ONE process group (leader pid in $XDG_RUNTIME_DIR/touch-gestures.pid),
# so `stop` leaves no orphans.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=/dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event   # Wacom HID 498D Finger
PIDF=${XDG_RUNTIME_DIR:-/tmp}/touch-gestures.pid
TAPD=$HERE/tapd

# Quickshell menu/launcher toggle: connect to its socket (see mango config.conf).
qs() { echo "socat -u /dev/null UNIX-CONNECT:\$XDG_RUNTIME_DIR/qs-$1-\$WAYLAND_DISPLAY.sock"; }
mm() { echo "mmsg dispatch $1"; }

build() {
  [[ -x $TAPD && $TAPD -nt $HERE/tapd.cpp ]] && return 0
  local cxx
  cxx=$(command -v g++ || ls -d /nix/store/*-gcc-wrapper-*/bin/g++ 2>/dev/null | head -1)
  [[ -n $cxx ]] || { echo "no g++ found; build tapd.cpp yourself" >&2; return 1; }
  "$cxx" -O2 -std=c++17 -Wall -Wextra -o "$TAPD" "$HERE/tapd.cpp"
}

alive() {   # pid file exists, process lives, and it really is this script
  local p; [[ -f $PIDF ]] || return 1
  p=$(cat "$PIDF"); [[ $p =~ ^[0-9]+$ ]] || return 1
  kill -0 "$p" 2>/dev/null && tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q touch-gestures
}

stop() {
  if alive; then kill -TERM -- "-$(cat "$PIDF")" 2>/dev/null; sleep 0.3; fi
  rm -f "$PIDF"
}

run() {   # group leader: stays alive, owns both children
  echo $$ >"$PIDF"
  trap 'trap - TERM INT EXIT; rm -f "$PIDF"; kill 0' TERM INT EXIT
  LOG=${XDG_RUNTIME_DIR:-/tmp}/touch-gestures.log
  exec 2>>"$LOG"
  export CMD_TAP3="$HOME/.config/hypr/spawn-alacritty.sh"   # 3-finger tap: terminal
  export CMD_TAP4='grim -g "$(slurp)" - | wl-copy'
  export CMD_TAP5="$HOME/.config/hypr/qs-lock.sh"
  export CMD_LONG1="$HERE/rclick.sh"          # 1-finger hold: right click at the touch point
  export CMD_LONG2="mmsg dispatch togglefloating client,\$TG_CLIENT"   # 2-finger hold: toggle floating of the window under them
  export CMD_PINCH_OUT="$(mm resizewin,+96,+54)"
  export CMD_PINCH_IN="$(mm resizewin,-96,-54)"
  # 2-finger drag moves a FLOATING window only when both fingers are on it (tapd asks mmsg for geometry).
  export TOUCH_MON=eDP-1   # monitor the touchscreen is mapped to
  # Swipes: CMD_SW_<fingers><dir>[_<edge>]. dir = R L U D (finger motion, device frame), edge = L R T B.
  export CMD_SW_1R_L="$(mm viewtoleft)"        # 1 finger, from left edge, to the right: previous tag
  export CMD_SW_1L_R="$(mm viewtoright)"       # 1 finger, from right edge, to the left: next tag
  export CMD_SW_1U_B="$(qs launcher)"          # 1 finger, from bottom edge, up: launcher
  export CMD_SW_1D_T="$(qs menu-audio)"        # 1 finger, from top edge, down: audio menu
  export CMD_SW_3U_B="$HOME/.config/hypr/toggle-wvkbd.sh"   # 3 fingers, from bottom edge, up: keyboard
  export CMD_SW_3U="$HOME/.config/mango/overview.sh toggle"      # 3 fingers up: overview
  export CMD_SW_3D='if mmsg get all-layers | grep -q "\"name\":\"wvkbd\""; then pkill -RTMIN -x wvkbd-mobintl; fi'   # 3 fingers down (anywhere): hide the keyboard if it is showing
  export CMD_SW_3R="$(mm viewtoleft)"          # 3 fingers right: previous tag
  export CMD_SW_3L="$(mm viewtoright)"         # 3 fingers left: next tag
  export CMD_SW_4D="$(mm killclient)"          # 4 fingers down: close window
  export CMD_SW_4U="$(qs menu-clip)"           # 4 fingers up: clipboard menu
  export CMD_SW_4R="$(mm tagtoleft)"           # 4 fingers right: move window to previous tag
  export CMD_SW_4L="$(mm tagtoright)"          # 4 fingers left: move window to next tag
  export CMD_SW_5R="$(mm focusdir,left)"       # 5 fingers right: focus left
  export CMD_SW_5L="$(mm focusdir,right)"      # 5 fingers left: focus right
  export CMD_SW_5U="$(mm togglefullscreen)"    # 5 fingers up: fullscreen
  "$TAPD" "$DEV" &
  wait -n   # if tapd dies, fall through: the EXIT trap cleans up the group
}


case "${1:-}" in
  start)   alive && { echo "already running"; exit 0; }; build || exit 1
           setsid "$0" _run >/dev/null 2>&1 & sleep 0.5; alive && echo started || { echo "failed to start" >&2; exit 1; } ;;
  stop)    stop; echo stopped ;;
  restart) stop; build || exit 1; setsid "$0" _run >/dev/null 2>&1 & sleep 0.5; alive && echo started || exit 1 ;;
  status)  alive && echo "running (group $(cat "$PIDF"))" || echo "not running" ;;
  _run)    run ;;
  *)       echo "usage: $0 start|stop|restart|status" >&2; exit 2 ;;
esac
