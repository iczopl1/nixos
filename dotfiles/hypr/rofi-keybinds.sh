#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
theme="${ROFI_KEYBINDS_THEME:-$config_dir/rofi-keybinds.rosi}"
hyprland_conf="$config_dir/hyprland.conf"
keybinds_conf="$config_dir/keybinds.conf"

if [[ "${1:-}" != "--print" ]] && ! command -v rofi >/dev/null 2>&1; then
  notify-send -a Hyprland "Keybinds" "rofi is required"
  exit 1
fi

keybind_rows="$(
awk '
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function strip_comment(s,    i, c, out, quote) {
  quote = ""
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if ((c == "\"" || c == "'\''") && (i == 1 || substr(s, i - 1, 1) != "\\")) {
      quote = quote == c ? "" : (quote == "" ? c : quote)
    }
    if (c == "#" && quote == "") {
      break
    }
    out = out c
  }
  return trim(out)
}

function expand_vars(s,    k) {
  for (k in vars) {
    gsub("\\$" k, vars[k], s)
  }
  return s
}

function display_len(s,    t) {
  t = s
  gsub(//, "W", t)
  gsub(//, "B", t)
  gsub(//, "B", t)
  return length(t)
}

function add_row(key, label,    n) {
  n = ++row_count
  row_key[n] = key
  row_label[n] = label
  if (display_len(key) > key_width) {
    key_width = display_len(key)
  }
}

function key_name(k) {
  k = trim(k)
  if (k == "SUPER_L") return ""
  if (k == "XF86AudioRaiseVolume") return "VOL+"
  if (k == "XF86AudioLowerVolume") return "VOL-"
  if (k == "XF86AudioMute") return "MUTE"
  if (k == "XF86AudioMicMute") return "MIC"
  if (k == "XF86MonBrightnessUp") return ""
  if (k == "XF86MonBrightnessDown") return ""
  if (k == "semicolon") return ";"
  if (k == "delete") return "Delete"
  if (k == "INSERT") return "Insert"
  if (k == "mouse:272") return "LMB"
  if (k == "mouse:273") return "RMB"
  if (k ~ /^[a-z]$/) return toupper(k)
  return k
}

function mods_name(m) {
  m = expand_vars(trim(m))
  gsub(/SUPER/, "", m)
  gsub(/SHIFT/, "S", m)
  gsub(/CTRL/, "C", m)
  gsub(/ALT/, "A", m)
  gsub(/[[:space:]]+/, "+", m)
  gsub(/\+\+/, "+", m)
  return m
}

function combo(mods, key,    m, k) {
  m = mods_name(mods)
  k = key_name(key)
  if (m == "") return k
  return m "+" k
}

function friendly(dispatcher, arg, raw,    cmd, out) {
  dispatcher = trim(dispatcher)
  arg = trim(arg)
  raw = trim(raw)
  cmd = expand_vars(arg)

  if (dispatcher == "exec") {
    if (raw ~ /\$menu/ || cmd ~ /rofi -show drun/) return "Open app launcher"
    if (raw ~ /\$lock/ || cmd ~ /hyprlock/) return "Lock screen"
    if (raw ~ /\$fileManager/) return "Open file manager"
    if (raw ~ /\$terminal/) return "Open terminal"
    if (raw ~ /\$web/) return "Open browser"
    if (raw ~ /\$clip/ || cmd ~ /clipboard/) return "Open clipboard history"
    if (raw ~ /\$emoji/ || cmd ~ /emoji/) return "Open emoji picker"
    if (raw ~ /\$ss/) return "Take screenshot"
    if (raw ~ /\$scriber/ || cmd ~ /wayscriber/) return "Toggle dictation"
    if (cmd ~ /rofi-bluetooth/) return "Open Bluetooth menu"
    if (cmd ~ /rofi-wallpaper/) return "Open wallpaper switcher"
    if (cmd ~ /rofi-keybinds/) return "Show keybind list"
    if (cmd ~ /waybar-toggle/) return "Toggle Waybar"
    if (cmd ~ /bgm-power-monitor.*toggle/) return "Toggle background music monitor"
    if (cmd ~ /bgm-power-monitor.*skip/) return "Skip background music track"
    if (cmd ~ /ttsmako-toggle/) return "Toggle notification speech"
    if (cmd ~ /toggle-wvkbd/) return "Toggle on-screen keyboard"
    if (cmd ~ /wpctl set-volume.*5%[+]/) return "Raise volume"
    if (cmd ~ /wpctl set-volume.*5%-/) return "Lower volume"
    if (cmd ~ /wpctl set-mute.*SINK/) return "Mute output"
    if (cmd ~ /wpctl set-mute.*SOURCE/) return "Mute microphone"
    if (cmd ~ /brightnessctl.*10%[+]/) return "Increase brightness"
    if (cmd ~ /brightnessctl.*10%-/) return "Decrease brightness"
    if (cmd ~ /cursor:zoom_factor.*1.1/) return "Increase cursor zoom"
    if (cmd ~ /cursor:zoom_factor.*0.9/) return "Decrease cursor zoom"
    if (cmd ~ /notify-send.*disabled/) return "Disable keybinds"
    if (cmd ~ /notify-send.*restored/) return "Restore keybinds"
    return cmd
  }

  if (dispatcher == "killactive") return "Close active window"
  if (dispatcher == "togglefloating") return "Toggle floating"
  if (dispatcher == "pseudo") return "Toggle pseudo tiling"
  if (dispatcher == "togglesplit") return "Toggle split"
  if (dispatcher == "fullscreen") return "Toggle fullscreen"
  if (dispatcher == "movefocus") {
    if (arg == "l") return "Focus left"
    if (arg == "r") return "Focus right"
    if (arg == "u") return "Focus up"
    if (arg == "d") return "Focus down"
  }
  if (dispatcher == "resizeactive") return "Resize active window " arg
  if (dispatcher == "movewindow") {
    if (arg == "l") return "Move window left"
    if (arg == "r") return "Move window right"
    if (arg == "u") return "Move window up"
    if (arg == "d") return "Move window down"
    return "Move window"
  }
  if (dispatcher == "resizewindow") return "Resize window"
  if (dispatcher == "workspace") {
    if (arg == "e-1") return "Previous workspace"
    if (arg == "e+1") return "Next workspace"
    return "Switch to workspace " arg
  }
  if (dispatcher == "movetoworkspace") return "Move window to workspace " arg
  if (dispatcher == "submap" && arg == "clean") return "Enter clean keybind submap"
  if (dispatcher == "submap" && arg == "reset") return "Return to normal keybinds"
  return dispatcher (arg == "" ? "" : " " arg)
}

function print_bind(raw,    line, pos, prefix, rest, part_count, parts, mods, key, dispatcher, arg, c, label) {
  line = strip_comment(raw)
  if (line == "") return
  if (line !~ /^bind[a-z]*[[:space:]]*=/) return

  pos = index(line, "=")
  prefix = trim(substr(line, 1, pos - 1))
  rest = trim(substr(line, pos + 1))
  part_count = split(rest, parts, /,/)
  if (part_count < 3) return

  mods = trim(parts[1])
  key = trim(parts[2])
  dispatcher = trim(parts[3])
  arg = ""
  for (c = 4; c <= part_count; c++) {
    arg = arg (arg == "" ? "" : ",") parts[c]
  }
  arg = trim(arg)
  if (arg ~ /rofi-super-hold\.sh/) return

  c = combo(mods, key)
  label = friendly(dispatcher, arg, raw)
  if (prefix ~ /^bindm/) label = label " by dragging"
  add_row(c, label)
}

/^[[:space:]]*\$/ {
  line = strip_comment($0)
  pos = index(line, "=")
  if (pos > 1) {
    name = trim(substr(line, 2, pos - 2))
    value = trim(substr(line, pos + 1))
    vars[name] = value
  }
  next
}

{
  lines[++line_count] = $0
}

END {
  add_row("", "Open icon app launcher")
  for (i = 1; i <= line_count; i++) {
    print_bind(lines[i])
  }
  for (i = 1; i <= row_count; i++) {
    padding = key_width + 1 - display_len(row_key[i])
    printf "%s%*s%s\n", row_key[i], padding, "", row_label[i]
  }
}
' "$hyprland_conf" "$keybinds_conf"
)"

if [[ "${1:-}" == "--print" ]]; then
  printf '%s\n' "$keybind_rows"
  exit 0
fi

printf '%s\n' "$keybind_rows" |
  rofi -dmenu -i -matching normal -p keys -window-title keybinds-rofi -theme "$theme"
