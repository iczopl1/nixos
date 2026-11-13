#!/usr/bin/env bash
# effects-ctl.sh – jeden program do włączania/wyłączania poszczególnych efektów
# graficznych Mango i Quickshell (zamiast grzebania w kilku różnych skrótach/skryptach).
#
# Użycie:
#   effects                          interaktywne menu (bez argumentów)
#   effects status                   stan wszystkich efektów
#   effects blur       [on|off]
#   effects shadows    [on|off]
#   effects animations [on|off]      animacje Mango (okna)
#   effects layer      [on|off]      layer_animations (animacje warstw Quickshell/bar)
#   effects particles  [off|leaves|rain|snow|sparks|cursor]
#   effects wpm                      przełącz obramówkę WPM (T3.13)
#   effects bar                      przełącz widoczność baru (SUPER+F11)
#
# Bez argumentu do blur/shadows/animations/layer: przełącza (toggle).

set -euo pipefail

CONF="$HOME/.config/mango/config.conf"
SOCK_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WL="${WAYLAND_DISPLAY:-wayland-1}"

mango_get() { grep -m1 "^$1=" "$CONF" 2>/dev/null | cut -d= -f2; }

mango_set() {
  local key="$1" val="$2"
  sed -i "s/^$key=.*/$key=$val/" "$CONF"
  mmsg dispatch reloadconfig >/dev/null 2>&1 || true
}

mango_toggle() {
  local key="$1"
  local cur; cur=$(mango_get "$key")
  if [[ "$cur" == "1" ]]; then mango_set "$key" 0; echo "$key: off"
  else                         mango_set "$key" 1; echo "$key: on"
  fi
}

mango_onoff() {
  local key="$1" mode="${2:-toggle}"
  case "$mode" in
    on)  mango_set "$key" 1; echo "$key: on" ;;
    off) mango_set "$key" 0; echo "$key: off" ;;
    *)   mango_toggle "$key" ;;
  esac
}

socket_ping() {
  # Połącz się z socketem QS, wyślij nic (sam connect wywołuje toggle po stronie QML)
  socat -u /dev/null "UNIX-CONNECT:$SOCK_DIR/$1-$WL.sock" 2>/dev/null || true
}

socket_send() {
  # Połącz się z socketem QS i wyślij linię tekstu (payload)
  printf '%s\n' "$2" | socat -u - "UNIX-CONNECT:$SOCK_DIR/$1-$WL.sock" 2>/dev/null || true
}

particles_set() {
  local theme="$1"
  case "$theme" in
    off|leaves|rain|snow|sparks|cursor) socket_send qs-particles-set "$theme" ;;
    *) echo "Nieznany motyw: $theme (off|leaves|rain|snow|sparks|cursor)" >&2; return 1 ;;
  esac
}

status() {
  echo "--- Mango (config.conf) ---"
  printf "  blur:              %s\n" "$(mango_get blur)"
  printf "  shadows:           %s\n" "$(mango_get shadows)"
  printf "  animations:        %s\n" "$(mango_get animations)"
  printf "  layer_animations:  %s\n" "$(mango_get layer_animations)"
  echo "--- Quickshell ---"
  printf "  particles:         %s\n" "$(cat "$HOME/.config/particle-effect" 2>/dev/null || echo off)"
  echo "  wpm border:        (socket toggle – stan tylko w QS)"
  echo "  bar:               (socket toggle – SUPER+F11)"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

cmd="${1:-menu}"
case "$cmd" in
  status)      status ;;
  blur)        mango_onoff blur       "${2:-}" ;;
  shadows)     mango_onoff shadows    "${2:-}" ;;
  animations)  mango_onoff animations "${2:-}" ;;
  layer)       mango_onoff layer_animations "${2:-}" ;;
  particles)   particles_set "${2:?podaj motyw: off|leaves|rain|snow|sparks|cursor}" ;;
  wpm)         socket_ping qs-wpm ;;
  bar)         socket_ping qs-bar ;;
  help|-h|--help) usage ;;
  menu)
    while true; do
      clear
      echo "=== Efekty graficzne (Mango / Quickshell) ==="
      status
      echo
      echo " 1) blur toggle        2) shadows toggle"
      echo " 3) animations toggle  4) layer_animations toggle"
      echo " 5) particles: off     6) particles: leaves"
      echo " 7) particles: rain    8) particles: snow"
      echo " 9) particles: sparks  c) particles: cursor (piksele za myszką)"
      echo " w) wpm border toggle  b) bar toggle         q) wyjście"
      read -rp "> " choice
      case "$choice" in
        1) mango_onoff blur ;;
        2) mango_onoff shadows ;;
        3) mango_onoff animations ;;
        4) mango_onoff layer_animations ;;
        5) particles_set off ;;
        6) particles_set leaves ;;
        7) particles_set rain ;;
        8) particles_set snow ;;
        9) particles_set sparks ;;
        c) particles_set cursor ;;
        w) socket_ping qs-wpm ;;
        b) socket_ping qs-bar ;;
        q) exit 0 ;;
        *) ;;
      esac
      sleep 1
    done
    ;;
  *)
    usage
    exit 1
    ;;
esac
