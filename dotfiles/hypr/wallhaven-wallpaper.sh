#!/usr/bin/env bash
# Usage: wallhaven-wallpaper.sh <full-image-url>
# Downloads that wallhaven image into ~/wpps and applies it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wpps}"
url="${1:?usage: $0 <image-url>}"
note() { notify-send -a wallhaven "Wallhaven" "$1" 2>/dev/null || true; }

name="$(basename "$url")"
case "$name" in wallhaven-*) ;; *) name="wallhaven-$name" ;; esac
dest="$WALLPAPER_DIR/$name"
mkdir -p "$WALLPAPER_DIR"
if [ ! -s "$dest" ]; then
  note "Downloading $name"
  curl -fsS --max-time 120 -o "$dest.part" "$url" || { rm -f "$dest.part"; note "Download failed"; exit 1; }
  mv "$dest.part" "$dest"
fi
exec "$SCRIPT_DIR/switch-random-wallpaper.sh" "$dest"
