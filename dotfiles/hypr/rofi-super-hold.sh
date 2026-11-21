#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr-super-hold-${UID}"
pid_file="$state_dir/timer.pid"
shown_file="$state_dir/shown"
canceled_file="$state_dir/canceled"
menu_cmd=("$config_dir/qs-launcher.sh")  # was: rofi -show drun -show-icons -theme "$config_dir/rofi-app-icon-grid.rosi"

mkdir -p "$state_dir"

cancel_timer() {
  if [[ -s "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}

case "${1:-}" in
  press)
    cancel_timer
    rm -f "$shown_file" "$canceled_file"
    ;;
  cancel)
    touch "$canceled_file"
    cancel_timer
    ;;
  release)
    if [[ -e "$canceled_file" ]]; then
      rm -f "$canceled_file" "$shown_file" "$pid_file"
      exit 0
    fi

    if [[ -e "$shown_file" ]]; then
      rm -f "$shown_file" "$pid_file"
      exit 0
    fi

    cancel_timer

    # skip a shell: poke the launcher's socket directly, fall back to the script (cold start)
    echo t | socat -u - "UNIX-CONNECT:${XDG_RUNTIME_DIR:-/tmp}/qs-launcher-${WAYLAND_DISPLAY:-wayland-0}.sock" 2>/dev/null ||
      "${menu_cmd[@]}"
    ;;
  *)
    printf 'usage: %s press|cancel|release\n' "$0" >&2
    exit 2
    ;;
esac
