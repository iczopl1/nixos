#!/bin/sh
# Cycle the focused monitor's tiling layout backwards (SUPER+SHIFT+grave).
# Walks mmsg's full layout list; switch_layout is the forward twin.
mmsg get all-monitors | timeout 5 python3 -c '
import json, subprocess, sys
mons = json.load(sys.stdin)["monitors"]
cur = next((m for m in mons if m["active"]), mons[0])
names = [l["name"] for l in json.loads(subprocess.check_output(["mmsg", "get", "layouts"]))["layouts"]]
print(names[(cur["layout_index"] - 1) % len(names)])
' | { read -r name && [ -n "$name" ] && mmsg dispatch "setlayout,$name"; }
