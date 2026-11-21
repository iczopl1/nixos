#!/usr/bin/env bash
# T3.7: Status telefonu GrapheneOS przez Tailscale.
# Wyjście: "online" | "offline" | "ts-off"
# Quickshell odpytuje co 30 s.

set -euo pipefail

PHONE_IP="100.98.94.124"   # Tailscale IP telefonu (nazwa w Tailscale: pixel-9-pro)

if ! command -v tailscale &>/dev/null; then echo "ts-off"; exit 0; fi

# Tailscale musi być zalogowany
tailscale status &>/dev/null || { echo "ts-off"; exit 0; }

# Ping – 1 pakiet, timeout 2 s
if ping -c1 -W2 "$PHONE_IP" &>/dev/null; then
    echo "online"
else
    echo "offline"
fi
