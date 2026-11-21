#!/usr/bin/env bash
# Usage: wallhaven-search.sh <query> [page]
# Search wallhaven (min 1920x1080, SFW). Downloads thumbnails, prints "id<TAB>full-url<TAB>thumb<TAB>resolution".
set -euo pipefail
query="${1:-}"
page="${2:-1}"
[ -n "$query" ] || exit 1
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wallhaven-thumbs"
mkdir -p "$CACHE"
resp="$(curl -fsS --max-time 20 -G https://wallhaven.cc/api/v1/search \
  --data-urlencode "q=$query" --data-urlencode "atleast=1920x1080" --data-urlencode "page=$page" \
  --data-urlencode "categories=111" --data-urlencode "purity=100" \
  --data-urlencode "sorting=relevance" \
  ${WALLHAVEN_API_KEY:+--data-urlencode "apikey=$WALLHAVEN_API_KEY"})"
rows="$(jq -r '.data[] | "\(.id)\t\(.path)\t\(.thumbs.large)\t\(.resolution)"' <<<"$resp")"
[ -n "$rows" ] || exit 0
while IFS=$'\t' read -r id _ thumb _; do
  [ -s "$CACHE/$id.jpg" ] || { curl -fsS --max-time 30 -o "$CACHE/$id.part" "$thumb" && mv "$CACHE/$id.part" "$CACHE/$id.jpg"; } &
done <<<"$rows"
wait
while IFS=$'\t' read -r id url _ res; do
  [ -s "$CACHE/$id.jpg" ] && printf '%s\t%s\t%s\t%s\n' "$id" "$url" "$CACHE/$id.jpg" "$res"
done <<<"$rows"
