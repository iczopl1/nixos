#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/apply-wal-theme.py"

while read -r pid cmd; do
  kill "$pid" || true
done < <(pgrep -af '^(/[^ ]*/)?[.]?waybar(-wrapped)?( |$)' | awk '{pid=$1; $1=""; sub(/^ /,""); print pid "\t" $0}')

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! pgrep -af '^(/[^ ]*/)?[.]?waybar(-wrapped)?( |$)' >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

"$SCRIPT_DIR/start-waybar.sh"
