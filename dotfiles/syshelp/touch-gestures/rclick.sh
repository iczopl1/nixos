#!/usr/bin/env bash
# Right click at the touch point. tapd sets TG_X / TG_Y (global screen pixels).
# ydotool only moves the pointer relatively, and its moves count about double here,
# so walk the pointer to the target in damped steps (each step = half of the error).
set -u
tx=${TG_X:?} ty=${TG_Y:?}
# Ripple + trail suppression in power-fx (does nothing if power-fx is not running, e.g. on battery).
( timeout 1 quickshell -p /home/iczo/syshelp/power-fx/shell.qml ipc call fx hold "$tx" "$ty" >/dev/null 2>&1 || true ) &
for _ in 1 2 3 4 5 6 7 8; do
  read -r cx cy < <(timeout 1 mmsg get cursorpos | grep -o -E '"[xy]":-?[0-9.]+' | cut -d: -f2 | paste -sd' ')
  [[ -n ${cx:-} && -n ${cy:-} ]] || exit 1
  read -r ex ey < <(awk -v a="$tx" -v b="$cx" -v c="$ty" -v d="$cy" 'BEGIN{printf "%d %d\n", a-b, c-d}')
  if (( ${ex#-} <= 3 && ${ey#-} <= 3 )); then break; fi
  read -r sx sy < <(awk -v a="$ex" -v b="$ey" 'BEGIN{printf "%d %d\n", a/2, b/2}')
  timeout 1 ydotool mousemove -x "$sx" -y "$sy"
  sleep 0.02
done
timeout 1 ydotool click 0xC1   # right button down + up
