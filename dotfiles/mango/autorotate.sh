#!/bin/sh
# Rotate eDP-1 to match the accelerometer (replaces iio-hyprland).
# monitor-sensor talks to iio-sensor-proxy; wlr-randr applies the transform.
monitor-sensor --accel | while read -r line; do
  case "$line" in
    *"orientation changed: normal"*)    t=normal ;;
    *"orientation changed: bottom-up"*) t=180 ;;
    *"orientation changed: left-up"*)   t=90 ;;
    *"orientation changed: right-up"*)  t=270 ;;
    *) continue ;;
  esac
  wlr-randr --output eDP-1 --transform "$t"
done
