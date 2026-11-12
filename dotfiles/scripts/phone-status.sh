#!/usr/bin/env bash
# T3.7: Status telefonu GrapheneOS przez Tailscale.
# Wyjście (jedna linia):  "online" | "offline" | "ts-off"
# Quickshell odpytuje ten skrypt co 30 s.
# Nazwa hosta szukana jako "pixel" (dopasowanie częściowe, bez rozróżniania wielkości).

set -euo pipefail

if ! command -v tailscale &>/dev/null; then echo "ts-off"; exit 0; fi

RAW=$(tailscale status --json 2>/dev/null) || { echo "ts-off"; exit 0; }

# Wymagany jq – standardowo w minimal
RESULT=$(printf '%s' "$RAW" | jq -r '
  .Peer // {} |
  to_entries[] |
  select(.value.HostName | ascii_downcase | test("pixel")) |
  if .value.Online then "online" else "offline" end
' 2>/dev/null | head -1)

echo "${RESULT:-offline}"
