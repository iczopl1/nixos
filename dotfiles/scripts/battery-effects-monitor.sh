#!/usr/bin/env bash
# battery-effects-monitor.sh – gasi WSZYSTKIE efekty "specjalne" (patrz effects-ctl.sh)
# gdy laptop nie jest podłączony do zasilacza, i wraca do zapamiętanych ustawień po
# podłączeniu. Sam nie zna żadnych efektów – przy każdej zmianie zasilania woła
# `effects reapply`, która robi całą pracę (effects-ctl.sh, ten sam plik stanu).
#
# exec_once w mango-autostart.conf. Jedna instancja (flock) – bezpieczny restart mango.
set -euo pipefail

EFFECTS="$HOME/.config/scripts/effects-ctl.sh"
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/battery-effects-monitor.lock"
POLL_SECONDS="${BATTERY_EFFECTS_POLL_SECONDS:-10}"

ac_online() {
  local ps
  for ps in /sys/class/power_supply/*; do
    [ -d "$ps" ] || continue
    case "$(cat "$ps/type" 2>/dev/null || true)" in
      Mains|USB|USB_C)
        [ "$(cat "$ps/online" 2>/dev/null || echo 0)" = "1" ] && return 0
        ;;
    esac
  done
  return 1
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "battery-effects-monitor: już działa, kończę" >&2
  exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

last_state="unknown"

while true; do
  state="battery"; ac_online && state="ac"
  if [ "$state" != "$last_state" ]; then
    bash "$EFFECTS" reapply >/dev/null 2>&1 || true
    last_state="$state"
  fi
  sleep "$POLL_SECONDS"
done
