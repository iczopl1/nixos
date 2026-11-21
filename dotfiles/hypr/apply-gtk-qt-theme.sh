#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
COLORS_SH="$CACHE_DIR/colors.sh"
[ -f "$COLORS_SH" ] || exit 0

set +u
source "$COLORS_SH"
set -u

brighten_hex() {
  local hex="${1#\#}"
  local boost="$2"
  local r g b

  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))

  r=$((r + boost))
  g=$((g + boost))
  b=$((b + boost))

  (( r > 255 )) && r=255
  (( g > 255 )) && g=255
  (( b > 255 )) && b=255

  printf '#%02x%02x%02x' "$r" "$g" "$b"
}

# Pick the higher-contrast of two candidates against $bg_hex.
# Uses perceived luminance (Rec. 601): Y = 0.299 R + 0.587 G + 0.114 B.
contrast_pick() {
  local bg_hex="${1#\#}"
  local light_hex="$2"
  local dark_hex="$3"
  local r g b y
  r=$((16#${bg_hex:0:2}))
  g=$((16#${bg_hex:2:2}))
  b=$((16#${bg_hex:4:2}))
  # scaled *1000 to keep integer math
  y=$(( (299 * r + 587 * g + 114 * b) / 1000 ))
  if (( y >= 140 )); then
    printf '%s' "$dark_hex"
  else
    printf '%s' "$light_hex"
  fi
}

bg="$(brighten_hex "$background" 28)"
fg="$foreground"
# panel="$color0"
panel="$(brighten_hex "$color0" 21)"
surface="$color2"
surface2="$color1"
accent="$color2"
accent2="$color2"
linkc="$color14" #14
warn="$color11"
err="$color9"
disabled="$color1" #8
selection="$(brighten_hex "$color4" -18)"
# Ensure readable text on top of selection / panel backgrounds.
selection_fg="$(contrast_pick "$selection" "$fg" "$color0")"
panel_fg="$(contrast_pick "$panel" "$fg" "$color0")"
surface_fg="$(contrast_pick "$surface" "$fg" "$color0")"

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.config/qt5ct/colors" "$HOME/.config/qt6ct/colors"

cat > "$HOME/.config/gtk-3.0/gtk.css" <<GTK
@define-color theme_bg_color ${bg};
@define-color theme_fg_color ${fg};
@define-color theme_base_color ${panel};
@define-color theme_text_color ${fg};
@define-color theme_selected_bg_color ${selection};
@define-color theme_selected_fg_color ${selection_fg};
@define-color insensitive_bg_color ${surface};
@define-color insensitive_fg_color ${disabled};
@define-color unfocused_bg_color ${bg};
@define-color unfocused_fg_color ${fg};
@define-color unfocused_base_color ${panel};
@define-color unfocused_text_color ${fg};
@define-color borders ${surface2};
@define-color warning_color ${warn};
@define-color error_color ${err};
@define-color success_color ${accent};
@define-color link_color ${linkc};

window, dialog, popover, menubar, toolbar, .background {
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}

entry, textview, treeview.view, iconview, viewport, scrolledwindow, notebook > stack {
  background-color: @theme_base_color;
  color: @theme_text_color;
  caret-color: @theme_text_color;
}

button, headerbar, .titlebar, .sidebar, notebook, placessidebar {
  background-color: @theme_bg_color;
  color: @theme_fg_color;
  border-color: @borders;
}

button:hover, row:hover, treeview.view:hover {
  background-color: ${selection};
  color: ${selection_fg};
}

selection, *:selected,
row:selected, treeview.view:selected, list row:selected {
  background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
}

row:selected label, treeview.view:selected, list row:selected label {
  color: ${selection_fg};
}
GTK

cp "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"

mkqt() {
  local path="$1"
  cat > "$path" <<QT
[ColorScheme]
active_colors=#ff${fg#\#}, #ff${bg#\#}, #ff${surface#\#}, #ff${surface2#\#}, #ff${panel#\#}, #ff${panel#\#}, #ff${fg#\#}, #ff${fg#\#}, #ff${fg#\#}, #ff${panel#\#}, #ff${bg#\#}, #ff000000, #ff${selection#\#}, #ff${selection_fg#\#}, #ff${accent#\#}, #ff${accent2#\#}, #ff${panel#\#}, #ffffffff, #ff000000, #ff${fg#\#}, #80${selection#\#}
disabled_colors=#ff${disabled#\#}, #ff${bg#\#}, #ff${surface#\#}, #ff${surface2#\#}, #ff${panel#\#}, #ff${panel#\#}, #ff${disabled#\#}, #ff${fg#\#}, #ff${disabled#\#}, #ff${panel#\#}, #ff${bg#\#}, #ff000000, #4d${selection#\#}, #66${fg#\#}, #ff${accent#\#}, #ff${accent2#\#}, #ff${panel#\#}, #ffffffff, #ff000000, #ff${fg#\#}, #80${selection#\#}
inactive_colors=#ff${fg#\#}, #ff${bg#\#}, #ff${surface#\#}, #ff${surface2#\#}, #ff${panel#\#}, #ff${panel#\#}, #ff${fg#\#}, #ff${fg#\#}, #ff${fg#\#}, #ff${panel#\#}, #ff${bg#\#}, #ff000000, #ff${selection#\#}, #ff${selection_fg#\#}, #ff${accent#\#}, #ff${accent2#\#}, #ff${panel#\#}, #ffffffff, #ff000000, #ff${fg#\#}, #80${selection#\#}
QT
}

mkqt "$HOME/.config/qt5ct/colors/wal.conf"
mkqt "$HOME/.config/qt6ct/colors/wal.conf"

cat > "$HOME/.config/qt5ct/qt5ct.conf" <<Q5
[Appearance]
color_scheme_path=$HOME/.config/qt5ct/colors/wal.conf
custom_palette=true
icon_theme=Adwaita
standard_dialogs=default
style=Fusion
Q5

cat > "$HOME/.config/qt6ct/qt6ct.conf" <<Q6
[Appearance]
color_scheme_path=$HOME/.config/qt6ct/colors/wal.conf
custom_palette=true
icon_theme=Adwaita
standard_dialogs=default
style=Fusion
Q6
