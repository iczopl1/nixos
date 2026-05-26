#!/usr/bin/env bash
set -euo pipefail

for busy_file in /sys/class/drm/card*/device/gpu_busy_percent; do
  [ -r "$busy_file" ] || continue
  usage="$(cat "$busy_file")"
  printf '{"text":"󰢮 %s%%","tooltip":"GPU usage: %s%%"}\n' "$usage" "$usage"
  exit 0
done

for temp_file in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
  [ -r "$temp_file" ] || continue
  temp_raw="$(cat "$temp_file")"
  temp="$(( temp_raw / 1000 ))"
  printf '{"text":"󰢮 %s°C","tooltip":"GPU temperature: %s°C"}\n' "$temp" "$temp"
  exit 0
done

printf '{"text":"󰢮 --","tooltip":"GPU stats unavailable"}\n'
