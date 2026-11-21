#!/usr/bin/env bash
# Re-apply saved app->sink routes to every new audio stream (apps recreate streams on pause/resume).
routes="${XDG_STATE_HOME:-$HOME/.local/state}/audio-routes"
touch "$routes"
declare -A seen
pw-dump -m | jq --unbuffered -r '.[] | select(.type=="PipeWire:Interface:Node" and .info.props["media.class"]=="Stream/Output/Audio")
  | "\(.id)\t\(.info.props["application.name"] // "")"' |
while IFS=$'\t' read -r id app; do
  [ -z "${seen[$id]:-}" ] || continue
  seen[$id]=1
  sink="$(awk -F'\t' -v a="$app" '$1==a { s=$2 } END { print s }' "$routes")"
  [ -z "$sink" ] || pw-metadata "$id" target.object "$sink" >/dev/null
done
