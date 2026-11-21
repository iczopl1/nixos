#!/usr/bin/env bash
# Show the weather chip animation for every weather type (AC only).
# usage: weather-preview.sh [SECS]        cycle all types, SECS each (default 5)
#        weather-preview.sh KIND          hold one: clear partly cloud fog drizzle rain snow storm
#        weather-preview.sh off           back to the real weather
f="$(dirname "$(readlink -f "$0")")/weather-preview.txt"
trap ': > "$f"' EXIT INT TERM
case "${1:-5}" in
  off) : > "$f"; exit 0 ;;
  clear|partly|cloud|fog|drizzle|rain|snow|storm) printf '%s' "$1" > "$f"; trap - EXIT; exit 0 ;;
esac
for k in clear partly cloud fog drizzle rain snow storm; do
  printf '%s' "$k" > "$f"; echo "$k"; sleep "${1:-5}"
done
