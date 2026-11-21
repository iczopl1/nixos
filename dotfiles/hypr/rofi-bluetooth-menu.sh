#!/usr/bin/env bash
set -euo pipefail

theme="${ROFI_BLUETOOTH_THEME:-$HOME/.config/hypr/rofi-bluetooth.rosi}"

if ! command -v rofi >/dev/null 2>&1; then
  echo "error: rofi is required" >&2
  exit 1
fi

if ! command -v bluetoothctl >/dev/null 2>&1; then
  echo "error: bluetoothctl is required" >&2
  exit 1
fi

power_state() {
  bluetoothctl show | awk -F': ' '/Powered:/ { print $2; exit }'
}

device_icon() {
  local info="$1"
  local paired connected trusted blocked
  paired="$(printf '%s\n' "$info" | awk -F': ' '/Paired:/ { print $2; exit }')"
  connected="$(printf '%s\n' "$info" | awk -F': ' '/Connected:/ { print $2; exit }')"
  trusted="$(printf '%s\n' "$info" | awk -F': ' '/Trusted:/ { print $2; exit }')"
  blocked="$(printf '%s\n' "$info" | awk -F': ' '/Blocked:/ { print $2; exit }')"

  if [ "$blocked" = "yes" ]; then
    printf '%s\n' ""
  elif [ "$connected" = "yes" ]; then
    printf '%s\n' ""
  elif [ "$paired" = "yes" ] || [ "$trusted" = "yes" ]; then
    printf '%s\n' ""
  else
    printf '%s\n' ""
  fi
}

device_label() {
  local name="$1"
  local info="$2"
  local paired connected trusted
  paired="$(printf '%s\n' "$info" | awk -F': ' '/Paired:/ { print $2; exit }')"
  connected="$(printf '%s\n' "$info" | awk -F': ' '/Connected:/ { print $2; exit }')"
  trusted="$(printf '%s\n' "$info" | awk -F': ' '/Trusted:/ { print $2; exit }')"

  local tags=()
  [ "$connected" = "yes" ] && tags+=("connected")
  [ "$paired" = "yes" ] && tags+=("paired")
  [ "$trusted" = "yes" ] && tags+=("trusted")

  local icon
  icon="$(device_icon "$info")"

  if [ "${#tags[@]}" -gt 0 ]; then
    printf '%s  %s [%s]\n' "$icon" "$name" "$(IFS=,; echo "${tags[*]}")"
  else
    printf '%s  %s\n' "$icon" "$name"
  fi
}

run_action() {
  local action="$1"
  case "$action" in
    power-on)
      bluetoothctl power on >/dev/null
      ;;
    power-off)
      bluetoothctl power off >/dev/null
      ;;
    open-manager)
      exec blueman-manager
      ;;
    scan)
      bluetoothctl scan on >/dev/null 2>&1 &
      ;;
  esac
}

device_menu() {
  local mac="$1"
  local info name connected trusted paired blocked
  info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
  [ -n "$info" ] || exit 0

  name="$(printf '%s\n' "$info" | awk -F': ' '/Name:/ { print $2; exit }')"
  connected="$(printf '%s\n' "$info" | awk -F': ' '/Connected:/ { print $2; exit }')"
  trusted="$(printf '%s\n' "$info" | awk -F': ' '/Trusted:/ { print $2; exit }')"
  paired="$(printf '%s\n' "$info" | awk -F': ' '/Paired:/ { print $2; exit }')"
  blocked="$(printf '%s\n' "$info" | awk -F': ' '/Blocked:/ { print $2; exit }')"

  local entries=()
  if [ "$connected" = "yes" ]; then
    entries+=("  Disconnect")
  else
    entries+=("  Connect")
  fi

  if [ "$trusted" = "yes" ]; then
    entries+=("  Untrust")
  else
    entries+=("  Trust")
  fi

  if [ "$blocked" = "yes" ]; then
    entries+=("  Unblock")
  else
    entries+=("  Block")
  fi

  if [ "$paired" = "yes" ]; then
    entries+=("  Remove")
  fi

  entries+=("  Back")

  local selection
  selection="$({ printf '%b\n' "${entries[@]}"; } | rofi -dmenu -i -p "$name" -theme "$theme")"

  case "$selection" in
    *"  Connect")
      bluetoothctl connect "$mac" >/dev/null
      ;;
    *"  Disconnect")
      bluetoothctl disconnect "$mac" >/dev/null
      ;;
    *"  Trust")
      bluetoothctl trust "$mac" >/dev/null
      ;;
    *"  Untrust")
      bluetoothctl untrust "$mac" >/dev/null
      ;;
    *"  Block")
      bluetoothctl block "$mac" >/dev/null
      ;;
    *"  Unblock")
      bluetoothctl unblock "$mac" >/dev/null
      ;;
    *"  Remove")
      bluetoothctl remove "$mac" >/dev/null
      ;;
    *"  Back"|"")
      exit 0
      ;;
  esac
}

entries=()
device_macs=()

if [ "$(power_state)" = "yes" ]; then
  entries+=("  Bluetooth: on")
else
  entries+=("  Bluetooth: off")
fi
entries+=("  Open Blueman")
entries+=("  Scan Devices")

while read -r _ mac name; do
  [ -n "${mac:-}" ] || continue
  info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
  [ -n "$info" ] || continue
  display_name="$name"
  if [ -z "$display_name" ]; then
    display_name="$mac"
  fi
  entries+=("$(device_label "$display_name" "$info")")
  device_macs+=("$mac")
done < <(bluetoothctl devices)

selection_index="$({ printf '%b\n' "${entries[@]}"; } | rofi -dmenu -i -p bluetooth -theme "$theme" -format i)"
[ -n "$selection_index" ] || exit 0

case "$selection_index" in
  0)
    if [ "$(power_state)" = "yes" ]; then
      run_action power-off
    else
      run_action power-on
    fi
    ;;
  1)
    run_action open-manager
    ;;
  2)
    run_action scan
    ;;
  *)
    device_idx=$((selection_index - 3))
    [ "$device_idx" -ge 0 ] || exit 0
    [ "$device_idx" -lt "${#device_macs[@]}" ] || exit 0
    device_menu "${device_macs[$device_idx]}"
    ;;
esac
