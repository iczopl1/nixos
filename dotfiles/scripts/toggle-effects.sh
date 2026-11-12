#!/usr/bin/env bash
# toggle-effects.sh – przełącza efekty graficzne Mango w locie.
# T3.12: minimal (X250) ↔ full (PC z RTX)
# Użycie: toggle-effects [on|off|status]
# Bez argumentu: przełącza.

CONF="$HOME/.config/mango/config.conf"

get_state() {
  val=$(grep -m1 '^blur=' "$CONF" | cut -d= -f2)
  [[ "$val" == "1" ]] && echo "on" || echo "off"
}

set_effects() {
  local mode="$1"   # on | off
  if [[ "$mode" == "on" ]]; then
    sed -i 's/^blur=.*/blur=1/'       "$CONF"
    sed -i 's/^shadows=.*/shadows=1/' "$CONF"
    sed -i 's/^animations=.*/animations=1/'       "$CONF"
    sed -i 's/^layer_animations=.*/layer_animations=1/' "$CONF"
  else
    sed -i 's/^blur=.*/blur=0/'       "$CONF"
    sed -i 's/^shadows=.*/shadows=0/' "$CONF"
    sed -i 's/^animations=.*/animations=0/'       "$CONF"
    sed -i 's/^layer_animations=.*/layer_animations=0/' "$CONF"
  fi
  # Przeładuj konfigurację Mango
  mmsg dispatch reloadconfig 2>/dev/null || true
}

case "${1:-toggle}" in
  on)     set_effects on;  notify-send "Efekty" "Włączone (blur, animacje)" -t 2000 ;;
  off)    set_effects off; notify-send "Efekty" "Wyłączone (X250 mode)" -t 2000 ;;
  status) echo "Efekty: $(get_state)" ;;
  toggle)
    if [[ "$(get_state)" == "on" ]]; then
      set_effects off; notify-send "Efekty" "Wyłączone" -t 2000
    else
      set_effects on;  notify-send "Efekty" "Włączone" -t 2000
    fi
    ;;
esac
