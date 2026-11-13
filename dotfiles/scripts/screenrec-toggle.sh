#!/usr/bin/env bash
# T2.35: toggle nagrywania ekranu (wl-screenrec).
# SUPER+F5 = start → ikona nagrywania w powiadomieniu; ponowne SUPER+F5 = stop + notif z plikiem.

PID_FILE="/tmp/screenrec.pid"
OUT_DIR="$HOME/Videos"
mkdir -p "$OUT_DIR"

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid"
        rm -f "$PID_FILE"
        notify-send "Nagrywanie" "Zatrzymano. Plik zapisany w $OUT_DIR" -i video-x-generic
    else
        rm -f "$PID_FILE"
    fi
else
    out="$OUT_DIR/rec_$(date +%Y%m%d_%H%M%S).mp4"
    wl-screenrec -f "$out" &
    echo $! > "$PID_FILE"
    notify-send "Nagrywanie" "Rozpoczęto → $out" -i media-record -u low
fi
