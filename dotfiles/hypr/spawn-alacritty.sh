#!/usr/bin/env bash
# Spawn alacritty with a per-instance jittered palette so each terminal
# feels slightly distinct while staying inside the current wal theme.
# Palette: $ALACRITTY_PALETTE (19 colors, set by dup-terminal.sh), else a random
# pre-jittered one written by wal-apply-theme.sh, else theme-jitter.py now.
# Windows open in a shared `alacritty --daemon` (skips GPU/process startup);
# alacritty-init.sh applies the palette inside the window. Falls back to a
# standalone alacritty for arguments create-window can't take or a dead daemon.
set -euo pipefail

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
COLORS_SH="$WAL_CACHE/colors.sh"
POOL="$WAL_CACHE/alacritty-palettes"
DAEMON_SOCK="${XDG_RUNTIME_DIR:-/tmp}/alacritty-daemon.sock"
INIT="$HOME/.config/hypr/alacritty-init.sh"

SAT_JITTER="${ALACRITTY_SAT_JITTER:-5}"
LIGHT_JITTER="${ALACRITTY_LIGHT_JITTER:-5}"
BG_BOOST="${ALACRITTY_BG_BOOST:-28}"

brighten_hex() {
  local hex="${1#\#}" boost="$2" r g b
  r=$((16#${hex:0:2} + boost)); (( r > 255 )) && r=255; (( r < 0 )) && r=0
  g=$((16#${hex:2:2} + boost)); (( g > 255 )) && g=255; (( g < 0 )) && g=0
  b=$((16#${hex:4:2} + boost)); (( b > 255 )) && b=255; (( b < 0 )) && b=0
  printf '#%02x%02x%02x' "$r" "$g" "$b"
}

# Fills `out` with 19 colors (bg fg bg_raw color0..color15), or leaves it empty.
pick_palette() {
  out=()
  if [ "$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/autobright/theme" 2>/dev/null)" != light ] &&
     [ -n "${ALACRITTY_PALETTE:-}" ]; then
    read -ra out <<< "$ALACRITTY_PALETTE"
    [ "${#out[@]}" -eq 19 ] && return
  fi
  # Light theme: the wal palette is dark. No override; the window uses wal-colors.toml.
  if [ "$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/autobright/theme" 2>/dev/null)" = light ]; then
    out=(); return 0
  fi
  if [ -s "$POOL" ] && [ "$POOL" -nt "$COLORS_SH" ]; then
    local pool
    mapfile -t pool < "$POOL"
    read -ra out <<< "${pool[RANDOM % ${#pool[@]}]}"
    [ "${#out[@]}" -eq 19 ] && return
  fi
  out=()
  local jitter
  jitter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/theme-jitter.py"
  [ -f "$COLORS_SH" ] && [ -f "$jitter" ] && command -v python3 >/dev/null 2>&1 || return 0

  # shellcheck disable=SC1090
  set +u; source "$COLORS_SH"; set -u
  local inputs=(
    "$(brighten_hex "$background" "$BG_BOOST")" "$foreground" "$background"
    "$color0" "$color1" "$color2" "$color3" "$color4" "$color5" "$color6" "$color7"
    "$color8" "$color9" "$color10" "$color11" "$color12" "$color13" "$color14" "$color15"
  )
  mapfile -t out < <(python3 "$jitter" --sat "$SAT_JITTER" --light "$LIGHT_JITTER" "${inputs[@]}")
  [ "${#out[@]}" -eq 19 ] || out=()
}

# Fills `opts` with KEY=VALUE color overrides from `out` (empty if no palette).
palette_opts() {
  opts=()
  [ "${#out[@]}" -eq 19 ] || return 0
  opts=(
    "colors.primary.background=\"${out[0]}\""
    "colors.primary.foreground=\"${out[1]}\""
    "colors.cursor.text=\"${out[2]}\""
    "colors.cursor.cursor=\"${out[1]}\""
    "colors.selection.background=\"${out[11]}\""
    "colors.normal.black=\"${out[3]}\""
    "colors.normal.red=\"${out[4]}\""
    "colors.normal.green=\"${out[5]}\""
    "colors.normal.yellow=\"${out[6]}\""
    "colors.normal.blue=\"${out[7]}\""
    "colors.normal.magenta=\"${out[8]}\""
    "colors.normal.cyan=\"${out[9]}\""
    "colors.normal.white=\"${out[10]}\""
    "colors.bright.black=\"${out[11]}\""
    "colors.bright.red=\"${out[12]}\""
    "colors.bright.green=\"${out[13]}\""
    "colors.bright.yellow=\"${out[14]}\""
    "colors.bright.blue=\"${out[15]}\""
    "colors.bright.magenta=\"${out[16]}\""
    "colors.bright.cyan=\"${out[17]}\""
    "colors.bright.white=\"${out[18]}\""
  )
}

# Opens the window in the daemon and exits; returns 1 if that isn't possible.
try_daemon() {
  local win=() cmd=() i
  while (( $# )); do
    case "$1" in
      --class|--working-directory|-T|--title) (( $# >= 2 )) || return 1; win+=("$1" "$2"); shift 2 ;;
      --hold) win+=("$1"); shift ;;
      -e|--command) shift; cmd=("$@"); break ;;
      *) return 1 ;;
    esac
  done
  [ -x "$INIT" ] || return 1
  # Like standalone alacritty: open in the caller's cwd, not the daemon's.
  [[ " ${win[*]} " == *" --working-directory "* ]] || win+=(--working-directory "$PWD")
  local req=(create-window "${win[@]}" -e "$INIT" "${opts[@]}" -- "${cmd[@]}")

  alacritty msg --socket "$DAEMON_SOCK" "${req[@]}" 2>/dev/null && exit 0

  # Start the daemon under a lock so parallel spawns don't start two.
  exec 9>"$DAEMON_SOCK.lock"
  flock -w 3 9 || return 1
  alacritty msg --socket "$DAEMON_SOCK" "${req[@]}" 2>/dev/null && exit 0
  # A live daemon that rejected the request: don't replace it, use standalone.
  pgrep -f "alacritty --daemon --socket $DAEMON_SOCK" >/dev/null && return 1
  rm -f "$DAEMON_SOCK"
  setsid -f env MALLOC_TRIM_THRESHOLD_=131072 MALLOC_ARENA_MAX=2 alacritty --daemon --socket "$DAEMON_SOCK" </dev/null >/dev/null 2>&1 9>&-
  for i in {1..40}; do
    sleep 0.05
    [ -S "$DAEMON_SOCK" ] && alacritty msg --socket "$DAEMON_SOCK" "${req[@]}" 2>/dev/null && exit 0
  done
  return 1
}

pick_palette
palette_opts
try_daemon "$@" || true

args=()
for o in "${opts[@]}"; do args+=(-o "$o"); done
exec alacritty "${args[@]}" "$@" 9>&-
