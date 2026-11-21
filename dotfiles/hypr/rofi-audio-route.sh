#!/usr/bin/env bash
set -euo pipefail
theme="$HOME/.config/hypr/rofi-audio-route.rosi"
pick() { rofi -dmenu -i -no-custom -format i -p "$1" -theme "$theme"; }
nodes="$(pw-dump | jq '[.[] | select(.type=="PipeWire:Interface:Node") | {id, state: .info.state, p: .info.props}]')"

mapfile -t apps < <(jq -r '.[] | select(.p["media.class"]=="Stream/Output/Audio" and .state=="running")
  | "\(.id)\t\(.p["application.name"] // .p["node.name"]) - \(.p["media.name"] // "")"' <<<"$nodes")
[ "${#apps[@]}" -gt 0 ] || { notify-send "Audio routing" "No app is playing audio"; exit 0; }
i="$(printf '%s\n' "${apps[@]#*$'\t'}" | pick app)" || exit 0

mapfile -t sinks < <(jq -r '.[] | select(.p["media.class"]=="Audio/Sink")
  | "\(.p["node.name"])\t\(.p["node.description"] // .p["node.name"])"' <<<"$nodes")
j="$(printf '%s\n' "${sinks[@]#*$'\t'}" | pick sink)" || exit 0

pw-metadata "${apps[i]%%$'\t'*}" target.object "${sinks[j]%%$'\t'*}" >/dev/null

# remember the choice per app so the watcher re-applies it to new streams
app="$(jq -r --argjson id "${apps[i]%%$'\t'*}" '.[] | select(.id==$id) | .p["application.name"] // empty' <<<"$nodes")"
[ -z "$app" ] || {
  routes="${XDG_STATE_HOME:-$HOME/.local/state}/audio-routes"
  { grep -vF "$app"$'\t' "$routes" 2>/dev/null || true; printf '%s\t%s\n' "$app" "${sinks[j]%%$'\t'*}"; } > "$routes.tmp"
  mv "$routes.tmp" "$routes"
}
