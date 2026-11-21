#!/usr/bin/env bash
# T3.13: Zmienia kolor obramówki aktywnego okna według WPM pisania w nvim.
# nvim zapisuje WPM do /tmp/nvim-wpm; ten skrypt polluje co 300 ms i ustawia focus_color.
# Uruchamiany przez nvim (InsertEnter) i zabijany przez nvim (InsertLeave + 2s).

WPM_FILE="/tmp/nvim-wpm-${UID}"
DEFAULT_COLOR="0x9eeaf9ff"  # spokój – błękit z config.conf

# Kolory progów (format mango: 0xRRGGBBAA)
color_for_wpm() {
  local wpm=$1
  if   [ "$wpm" -ge 70 ]; then echo "0xf7768eff"   # czerwień
  elif [ "$wpm" -ge 45 ]; then echo "0xff9e64ff"   # pomarańcz
  elif [ "$wpm" -ge 20 ]; then echo "0xe0af68ff"   # bursztyn
  else                         echo "0x9eeaf9ff"   # błękit
  fi
}

cleanup() {
  mmsg dispatch setoption,focus_color,"$DEFAULT_COLOR" 2>/dev/null
  exit 0
}
trap cleanup EXIT INT TERM

while true; do
  if [ -f "$WPM_FILE" ]; then
    wpm=$(cat "$WPM_FILE" 2>/dev/null)
    wpm=${wpm:-0}
    color=$(color_for_wpm "$wpm")
    mmsg dispatch setoption,focus_color,"$color" 2>/dev/null
  else
    # Plik zniknął – tryb insert opuszczony, wróć do domyślnego i zakończ
    mmsg dispatch setoption,focus_color,"$DEFAULT_COLOR" 2>/dev/null
    exit 0
  fi
  sleep 0.3
done
