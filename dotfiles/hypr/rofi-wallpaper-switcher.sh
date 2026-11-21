#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wpps}"
THEME_FILE="${ROFI_WALLPAPER_THEME:-$SCRIPT_DIR/rofi-wallpaper-grid.rasi}"
THUMB_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-wallpaper-thumbs"
LEGACY_HUE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-wallpaper-hues"
MANIFEST_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-wallpaper-manifest.tsv"
THUMB_SIZE="${ROFI_WALLPAPER_THUMB_SIZE:-512}"
HUE_START="${ROFI_WALLPAPER_HUE_START:-$((RANDOM % 360))}"

if ! [[ "$HUE_START" =~ ^[0-9]+$ ]]; then
  echo "error: ROFI_WALLPAPER_HUE_START must be a number from 0 to 359" >&2
  exit 1
fi
HUE_START="$((10#$HUE_START % 360))"

if [[ "${1:-}" != "--list" ]] && ! command -v rofi >/dev/null 2>&1; then
  echo "error: rofi is required" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "error: imagemagick is required" >&2
  exit 1
fi

if [ ! -d "$WALLPAPER_DIR" ]; then
  echo "error: wallpaper directory not found: $WALLPAPER_DIR" >&2
  exit 1
fi

mapfile -t wallpaper_records < <(find -L "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
  -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \
\) -printf '%p\t%T@:%s\n' | awk -F $'\t' '{
  split($2, fingerprint, ":")
  printf "%s\t%d:%s\n", $1, fingerprint[1], fingerprint[2]
}' | LC_ALL=C sort)

if [ "${#wallpaper_records[@]}" -eq 0 ]; then
  echo "error: no wallpapers available" >&2
  exit 1
fi

mkdir -p "$THUMB_CACHE_DIR" "$(dirname "$MANIFEST_FILE")"

cache_key_for() {
  local wallpaper="$1"
  local fingerprint="$2"
  printf '%s:%s\n' "$wallpaper" "$fingerprint" | sha1sum | awk '{print $1}'
}

hue_for() {
  local wallpaper="$1"
  local hue saturation brightness

  read -r hue saturation brightness < <(
    magick "$wallpaper[0]" \
      -auto-orient \
      -resize 1x1! \
      -colorspace HSB \
      -format '%[fx:round(360*u.r)] %[fx:round(1000*u.g)] %[fx:round(1000*u.b)]\n' \
      info:
  )

  printf '%03d\t%04d\t%04d\n' "$((hue % 360))" "$saturation" "$brightness"
}

thumbnail_for() {
  local wallpaper="$1"
  local thumbnail="$2"

  if [ ! -f "$thumbnail" ]; then
    magick "$wallpaper[0]" \
      -auto-orient \
      -gravity center \
      -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
      "$thumbnail"
  fi
}

declare -A cached_records=()
if [ -f "$MANIFEST_FILE" ]; then
  while IFS=$'\t' read -r wallpaper fingerprint hue saturation brightness thumbnail; do
    [ -n "${wallpaper:-}" ] || continue
    cached_records["$wallpaper"$'\t'"$fingerprint"]="$hue"$'\t'"$saturation"$'\t'"$brightness"$'\t'"$thumbnail"
  done < "$MANIFEST_FILE"
fi

sort_records=()
manifest_records=()
for record in "${wallpaper_records[@]}"; do
  IFS=$'\t' read -r wallpaper fingerprint <<< "$record"
  cached="${cached_records["$wallpaper"$'\t'"$fingerprint"]:-}"

  if [ -n "$cached" ]; then
    IFS=$'\t' read -r hue saturation brightness thumbnail <<< "$cached"
  else
    cache_key="$(cache_key_for "$wallpaper" "$fingerprint")"
    thumbnail="$THUMB_CACHE_DIR/$cache_key.png"
    if [ -f "$LEGACY_HUE_CACHE_DIR/$cache_key" ]; then
      read -r hue saturation brightness < "$LEGACY_HUE_CACHE_DIR/$cache_key"
    else
      read -r hue saturation brightness < <(hue_for "$wallpaper")
    fi
  fi

  thumbnail_for "$wallpaper" "$thumbnail"
  rotated_hue="$(((10#$hue - HUE_START + 360) % 360))"
  sort_records+=("$(printf '%03d\t%s\t%s\t%s\t%s\t%s' "$rotated_hue" "$hue" "$saturation" "$brightness" "$wallpaper" "$thumbnail")")
  manifest_records+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$wallpaper" "$fingerprint" "$hue" "$saturation" "$brightness" "$thumbnail")")
done
printf '%s\n' "${manifest_records[@]}" > "$MANIFEST_FILE"

wallpapers=()
entries=()
while IFS=$'\t' read -r _rotated_hue _hue _saturation _brightness wallpaper thumbnail; do
  wallpapers+=("$wallpaper")
  entries+=("${wallpaper##*/}\0icon\x1f$thumbnail")
done < <(printf '%s\n' "${sort_records[@]}" | LC_ALL=C sort -t $'\t' -k1,1n -k3,3nr -k4,4nr -k5,5)

# for the Quickshell wallpaper menu (~/.config/quickshell/bar/menus/Wallpaper.qml): "<wallpaper>\t<thumbnail>" per line, sorted
if [[ "${1:-}" == "--list" ]]; then
  for i in "${!wallpapers[@]}"; do
    printf '%s\t%s\n' "${wallpapers[i]}" "${entries[i]##*\\x1f}"
  done
  exit 0
fi

selection="$(printf '%b\n' "${entries[@]}" | rofi -dmenu -i -p wallpaper -theme "$THEME_FILE" -show-icons -format i)"

if [ -z "$selection" ]; then
  exit 0
fi

exec "$SCRIPT_DIR/switch-random-wallpaper.sh" "${wallpapers[$selection]}"
