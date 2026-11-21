#!/bin/sh
# Streams one line per NEW file ("+name") or DELETED known file ("-name") Syncthing finishes writing into the "Sync" folder.
# Event-driven (Syncthing events long-poll). Edits/re-syncs of known files are ignored:
# a file counts as new only if its path was not in ~/sync before (snapshot at start, kept in sync with deletes).
CFG="$HOME/.config/syncthing/config.xml"
K=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$CFG" | head -1)
F=$(sed -n 's:.*<folder id="\([^"]*\)" label="Sync".*:\1:p' "$CFG" | head -1)
URL="http://127.0.0.1:8384/rest/events"
KNOWN=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/phone-known.XXXXXX") || exit 1
trap 'rm -f "$KNOWN"' EXIT
(cd "$HOME/sync" 2>/dev/null && find . -type f ! -name '.syncthing.*' ! -name '*.tmp' | sed 's:^\./::') > "$KNOWN"
since=$(curl -s -m 10 -H "X-API-Key: $K" "$URL?events=ItemFinished&limit=1" | jq -r '.[-1].id // 0')
while :; do
  out=$(curl -s -m 70 -H "X-API-Key: $K" "$URL?events=ItemFinished&since=$since&timeout=60") || { sleep 5; continue; }
  [ -z "$out" ] && { sleep 5; continue; }
  last=$(printf '%s' "$out" | jq -r '.[-1].id // empty') || { sleep 5; continue; }
  [ -z "$last" ] && { sleep 5; continue; }
  since=$last
  printf '%s' "$out" | jq -r --arg f "$F" '.[] | select(.data.folder==$f and .data.type=="file" and .data.error==null) | "\(.data.action)\t\(.data.item)"' |
  while IFS="$(printf '\t')" read -r act item; do
    case "$item" in .syncthing.*|*.tmp|*/.syncthing.*) continue ;; esac
    if [ "$act" = delete ]; then
      if grep -qxF -- "$item" "$KNOWN"; then
        grep -vxF -- "$item" "$KNOWN" > "$KNOWN.n"; mv "$KNOWN.n" "$KNOWN"
        printf -- '-%s\n' "$item"
      fi
    elif ! grep -qxF -- "$item" "$KNOWN"; then
      printf '%s\n' "$item" >> "$KNOWN"
      printf '+%s\n' "$item"
    fi
  done
done
