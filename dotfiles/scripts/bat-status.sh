#!/usr/bin/env bash
# Zwraca "XX Charging|Discharging|Full" – jeden wiersz dla Quickshell.
now=0; full=0; st="Discharging"
for d in /sys/class/power_supply/BAT*/; do
  [ -f "$d/energy_now" ]  && now=$((now  + $(cat "$d/energy_now")))
  [ -f "$d/energy_full" ] && full=$((full + $(cat "$d/energy_full")))
  s=$(cat "$d/status" 2>/dev/null)
  [ "$s" = "Charging" ] || [ "$s" = "Full" ] && st="$s"
done
if [ "$full" -gt 0 ]; then
  echo "$((now * 100 / full)) $st"
else
  cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo -1)
  s=$(cat   /sys/class/power_supply/BAT0/status   2>/dev/null || echo Discharging)
  echo "$cap $s"
fi
