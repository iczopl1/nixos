#!/usr/bin/env bash
# Syncthing status dla paska – zwraca jedną linię tekstu.
# Wywoływany przez Quickshell co 30s.
# Wyjście: "sync OK 2/3" | "sync 87% 1/3" | "sync off" | "sync ?"

CONF="$HOME/.config/syncthing/config.xml"
API="http://localhost:8384"

# Klucz API z config.xml
API_KEY=$(awk -F'[<>]' '/<apikey>/{print $3; exit}' "$CONF" 2>/dev/null)
if [[ -z "$API_KEY" ]]; then
  echo "sync ?"
  exit 0
fi

# Ping – czy demon działa
PING=$(curl -sf -m 2 -H "X-API-Key: $API_KEY" "$API/rest/system/ping" 2>/dev/null)
if [[ "$PING" != *"pong"* ]]; then
  echo "sync off"
  exit 0
fi

# Połączone urządzenia
CONNS=$(curl -sf -m 3 -H "X-API-Key: $API_KEY" "$API/rest/system/connections" 2>/dev/null)
CONN_STR=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    c = d.get('connections', {})
    n = sum(1 for v in c.values() if v.get('connected'))
    t = len(c)
    print(f'{n}/{t}')
except: print('?')
" <<< "$CONNS" 2>/dev/null)

# Procent synchronizacji (globalny)
COMP=$(curl -sf -m 3 -H "X-API-Key: $API_KEY" "$API/rest/db/completion" 2>/dev/null)
PCT=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(int(d.get('completion', 0)))
except: print(-1)
" <<< "$COMP" 2>/dev/null)

if [[ "$PCT" == "100" ]]; then
  echo "sync OK $CONN_STR"
elif [[ "$PCT" -ge 0 ]]; then
  echo "sync ${PCT}% $CONN_STR"
else
  echo "sync ? $CONN_STR"
fi
