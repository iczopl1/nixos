# hint-click: label overlay -> click / press-and-hold at the chosen target.
#   ab / 1ab  left click      2ab  middle click      3ab  right click
#   4ab       press and hold left (drag start); the next pick drops there
# Boxes: AT-SPI fields first, vision as fallback. HINT_MODE=vision forces vision.
# Extra args go to wl-kbptr. DRY_RUN=1 prints actions instead of doing them.

# No /tmp fallback: a predictable name there could be pre-created by another user.
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}"
hold_file="$XDG_RUNTIME_DIR/hint-click.hold"

run() {
  if [[ -n "${DRY_RUN:-}" ]]; then echo "$*"; else "$@"; fi
}

# Prefer real clickable fields from the accessibility tree (AT-SPI): browsers,
# GTK/Qt apps, waybar, Electron started with --force-renderer-accessibility.
# Windows that expose nothing (terminals, TUIs, canvas apps) get picture-based boxes
# inside that window only. Whole-screen vision happens only with HINT_MODE=vision.
hint_atspi="${HINT_ATSPI:-hint-atspi}"
sock="$XDG_RUNTIME_DIR/hint-atspi.sock"
ver="@ver@"
rects=""
rc=3
if [[ "${HINT_MODE:-auto}" != vision ]]; then
  got=""
  # A warm helper daemon answers in ~0.1 s; a cold start costs ~0.6 s of
  # Python/OpenCV loading. HINT_ATSPI (tests) always runs that program directly.
  if [[ -z "${HINT_ATSPI:-}" && -S "$sock" ]]; then
    reply=$(printf 'full %s\n' "$ver" | socat -T3 - "UNIX-CONNECT:$sock" 2>/dev/null) || reply=""
    rc=${reply%%$'\n'*}
    if [[ "$rc" =~ ^[0-9]+$ ]]; then
      got=1
      rects=""
      [[ "$reply" == *$'\n'* ]] && rects=${reply#*$'\n'} # $(...) drops a trailing newline: "3" alone = no boxes
    fi
  fi
  if [[ -z "$got" ]]; then
    # No daemon yet (first press after login): start one for next time, answer cold now.
    if [[ -z "${HINT_ATSPI:-}" ]]; then
      HINT_ATSPI_VER="$ver" setsid "$hint_atspi" --serve >/dev/null 2>&1 </dev/null &
    fi
    rc=0
    rects=$(timeout 3 "$hint_atspi" 2>/dev/null) || rc=$? # a hung bus ends in rc 124: error notice, no hints
  fi
fi

# Mango has no command to put the cursor at x,y, so there wl-kbptr moves (and clicks)
# by itself. A drop only moves; the release follows below. Prefix 4 (hold) is a plain
# left click on Mango.
mango=""
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && mango=1
pick() {
  if [[ -z "$mango" ]]; then
    wl-kbptr -p -o modes=floating,click "$@"
  elif [[ -e "$hold_file" ]]; then
    wl-kbptr -o modes=floating "$@" >/dev/null && echo drop
  else
    wl-kbptr -o modes=floating,click "$@" >/dev/null
  fi
}

if [[ "$rc" == 0 && -n "$rects" ]]; then
  # -o cannot override the config file, so layer source=stdin on top of it.
  # Few forks on purpose: this runs on every press. The directory is private (0700).
  cfg="$XDG_RUNTIME_DIR/hint-click.$$"
  trap 'rm -f "$cfg"' EXIT
  user_cfg=""
  [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/wl-kbptr/config" ]] && user_cfg=$(<"${XDG_CONFIG_HOME:-$HOME/.config}/wl-kbptr/config")
  printf '%s\n\n[mode_floating]\nsource=stdin\n' "$user_cfg" >"$cfg" || exit 1
  out=$(pick -c "$cfg" "$@" <<<"$rects") || exit 0
elif [[ "${HINT_MODE:-auto}" == vision ]]; then
  # Only when you ask for it (HINT_MODE=vision): whole-screen picture detection.
  out=$(pick "$@") || exit 0
else
  # No automatic whole-desktop vision: a slow or broken helper must show up as a
  # problem, not be hidden behind guessed boxes over the bar and every window.
  notify-send -t 2500 -a Hyprland "hint-click" "No hints: helper failed (rc=$rc). Try again." 2>/dev/null || true
  exit 1
fi
[[ -n "$out" ]] || exit 0 # cancelled
if [[ "$out" == drop ]]; then # Mango: wl-kbptr already moved the cursor
  run ydotool mousemove -x 1 -y 0
  run ydotool mousemove -x -1 -y 0
  run ydotool click 0x80
  run rm -f "$hold_file"
  exit 0
fi

# "WxH+X+Y +OX+OY B"; target is output-local, add the output offset.
read -r area offset button <<<"$out"
IFS='x+' read -r w h x y <<<"$area"
IFS='+' read -r _ ox oy <<<"$offset"
for v in "$w" "$h" "$x" "$y" "$ox" "$oy"; do
  [[ "$v" =~ ^-?(0|[1-9][0-9]{0,5})$ ]] || exit 0 # never feed odd text into $(( ))
done
cx=$((ox + x + w / 2))
cy=$((oy + y + h / 2))

run hyprctl -q dispatch movecursor "$cx" "$cy"

if [[ -e "$hold_file" ]]; then
  # Dropping: wiggle so the app sees motion over the target, then release.
  run ydotool mousemove -x 1 -y 0
  run ydotool mousemove -x -1 -y 0
  run ydotool click 0x80
  run rm -f "$hold_file"
  exit 0
fi

case "$button" in
  l) run ydotool click 0xC0 ;;
  m) run ydotool click 0xC2 ;;
  r) run ydotool click 0xC1 ;;
  h)
    run ydotool click 0x40
    # Move a bit past the drag threshold so the app starts the drag now.
    run ydotool mousemove -x 6 -y 6
    run touch "$hold_file"
    run notify-send -t 2500 -a Hyprland "Holding" "SUPER+D and pick the drop target · Esc in cursor mode releases"
    ;;
esac
