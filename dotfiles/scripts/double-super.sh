#!/usr/bin/env bash
# Otwiera rofi po podwójnym wciśnięciu Super (window: 350ms).
# Użycie w mango config: bind=NONE,super_l,spawn_shell,~/.config/scripts/double-super.sh

STAMP="/tmp/.super_double_tap"
WINDOW_MS=350

NOW=$(date +%s%3N)

if [[ -f "$STAMP" ]]; then
    PREV=$(cat "$STAMP")
    DIFF=$((NOW - PREV))
    rm -f "$STAMP"
    if [[ $DIFF -le $WINDOW_MS ]]; then
        rofi -show drun -theme ~/.config/rofi/rofi.rosi
    fi
else
    echo "$NOW" > "$STAMP"
    # Usuń plik po upływie okna żeby stary tap nie "czekał" w nieskończoność
    (sleep 0.4 && rm -f "$STAMP") &
fi
