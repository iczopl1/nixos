#!/usr/bin/env bash
# T3.7: Przełącza słuchawki BT między PC a telefonem.
# MAC słuchawek: plik ~/.config/bt-headset-mac (jeden MAC, jedna linia).
# Jeśli pliku nie ma – auto-detect: pierwsza sparowana karta audio BT.
# Połącz na PC = rozłącz od telefonu (większość słuchawek jedno-punkt).
# Rozłącz od PC = telefon może się połączyć ponownie.

set -uo pipefail

CONF="$HOME/.config/bt-headset-mac"

get_mac() {
    if [ -f "$CONF" ]; then
        head -1 "$CONF" | tr -d '[:space:]'
        return
    fi
    # Auto-detect: urządzenia z "Audio" w profilu (A2DP lub HFP)
    bluetoothctl devices 2>/dev/null | while read -r _ mac _name; do
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        if printf '%s' "$info" | grep -qiE "UUID.*Audio|A2DP|HFP"; then
            echo "$mac"
            return
        fi
    done
}

MAC=$(get_mac)

if [ -z "${MAC:-}" ]; then
    notify-send "BT Headset" "Nie znaleziono sparowanych słuchawek.\nUtwórz ~/.config/bt-headset-mac z MAC adresem." \
        --icon=bluetooth --urgency=normal 2>/dev/null || true
    exit 1
fi

CONNECTED=$(bluetoothctl info "$MAC" 2>/dev/null | grep -c "Connected: yes" || true)

if [ "$CONNECTED" -ge 1 ]; then
    bluetoothctl disconnect "$MAC" >/dev/null 2>&1 &
    notify-send "BT Headset" "Rozłączono od PC\nTelefon może się teraz połączyć." \
        --icon=bluetooth 2>/dev/null || true
else
    bluetoothctl connect "$MAC" >/dev/null 2>&1 &
    notify-send "BT Headset" "Łączę z PC…" \
        --icon=bluetooth 2>/dev/null || true
fi
