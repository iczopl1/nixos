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
#   effects wpm-count                przełącz liczenie WPM (zatrzymuje evtest - oszczędza CPU)
#   effects wpm-color                przełącz kolor obramówki wg prędkości pisania (T3.13)
#   effects wpm-move                 przełącz "ruszanie się" okna (border_px/gap + puls) przy pisaniu
#   effects cava       [on|off]      wizualizator muzyki na pulpicie (cava-bg, na środku)
#   effects bar                      przełącz widoczność baru (SUPER+F11)
#
# Bez argumentu do blur/shadows/animations/layer: przełącza (toggle).

set -euo pipefail

CONF="$HOME/.config/mango/config.conf"
STATE="$HOME/.config/mango-effects"
SOCK_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WL="${WAYLAND_DISPLAY:-wayland-1}"

# UWAGA: config.conf to symlink (L+ w dotfiles.nix) wprost do repo – wraca do wartości
# wpisanych tam na stałe przy każdym starcie mango. Dlatego stan blur/shadows/animations/
# layer_animations NIE jest już zapisywany sed-em do config.conf (zostawało to zgubione przy
# restarcie), tylko w ~/.config/mango-effects + stosowany od razu przez mmsg dispatch.
# Przywracane po starcie mango przez mango-effects-restore.sh (exec_once w config.conf).
mango_state_get() { grep -m1 "^$1=" "$STATE" 2>/dev/null | cut -d= -f2; }

mango_state_set() {
  local key="$1" val="$2"
  touch "$STATE"
  if grep -q "^$key=" "$STATE" 2>/dev/null; then
    sed -i "s/^$key=.*/$key=$val/" "$STATE"
  else
    echo "$key=$val" >> "$STATE"
  fi
}

mango_get() {
  local v; v=$(mango_state_get "$1")
  if [ -n "$v" ]; then echo "$v"; else grep -m1 "^$1=" "$CONF" 2>/dev/null | cut -d= -f2; fi
}

mango_set() {
  local key="$1" val="$2"
  mmsg dispatch "setoption,$key,$val" >/dev/null 2>&1 || true
  mango_state_set "$key" "$val"
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

cava_running() {
  pgrep -f 'kitty.*kitten panel .*cava-bg' >/dev/null 2>&1
}

# UWAGA: bgm-power-monitor.sh sam odpala/zabija cava-bg wg stanu zasilania (poll co 5s) –
# ręczne wyłączenie tutaj może zostać nadpisane przy następnej zmianie AC/baterii.
cava_set() {
  local mode="${1:-toggle}"
  case "$mode" in
    on)
      cava_running && { echo "cava: już włączone"; return; }
      local launcher="$HOME/.config/scripts/launch-cava-bg.sh"
      [ -x "$launcher" ] && nohup "$launcher" >/dev/null 2>&1 &
      disown 2>/dev/null || true
      echo "cava: on"
      ;;
    off)
      pkill -f 'kitty.*kitten panel .*cava-bg' >/dev/null 2>&1 || true
      pkill -f 'cava -p .*/config-bg' >/dev/null 2>&1 || true
      echo "cava: off"
      ;;
    *)
      if cava_running; then cava_set off; else cava_set on; fi
      ;;
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
  echo "  wpm-count:         (socket toggle – zatrzymuje evtest, stan tylko w QS)"
  echo "  wpm-color:         (socket toggle – stan tylko w QS)"
  echo "  wpm-move:          (socket toggle – stan tylko w QS)"
  echo "  bar:               (socket toggle – SUPER+F11)"
  echo "--- Pulpit ---"
  if cava_running; then printf "  cava (muzyka):     on\n"; else printf "  cava (muzyka):     off\n"; fi
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
  wpm-count)   socket_ping qs-wpm-count ;;
  wpm-color)   socket_ping qs-wpm-color ;;
  wpm-move)    socket_ping qs-wpm-move ;;
  cava)        cava_set "${2:-toggle}" ;;
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
      echo " 9) particles: sparks  p) particles: cursor (piksele za myszką)"
      echo " n) wpm liczenie toggle (CPU)  k) wpm kolor toggle   r) wpm ruch toggle"
      echo " m) cava (muzyka) toggle       b) bar toggle          q) wyjście"
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
        p) particles_set cursor ;;
        n) socket_ping qs-wpm-count ;;
        k) socket_ping qs-wpm-color ;;
        r) socket_ping qs-wpm-move ;;
        m) cava_set toggle ;;
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
