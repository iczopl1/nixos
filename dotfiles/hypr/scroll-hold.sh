#!/usr/bin/env bash
# scroll-hold.sh start DX DY | stop
# Repeats wheel steps while a key is held. Hyprland's own key repeat (binde)
# stops as soon as a scroll event arrives, so cursor mode drives it from here.
pidfile="${XDG_RUNTIME_DIR:-/tmp}/scroll-hold.pid"

stop() {
  [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null
  rm -f "$pidfile"
}

case "$1" in
  start)
    stop
    ydotool mousemove -w -x "$2" -y "$3"
    (
      sleep 0.3                      # like key-repeat delay
      end=$((SECONDS + 20))          # safety cap if a release gets lost
      while ((SECONDS < end)); do
        ydotool mousemove -w -x "$2" -y "$3"
        sleep 0.04
      done
      rm -f "$pidfile"
    ) &
    echo $! >"$pidfile"
    ;;
  stop) stop ;;
esac
