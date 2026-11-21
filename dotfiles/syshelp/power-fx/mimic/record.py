#!/usr/bin/env python3
"""Record the cursor path for the `mimic` mouse dance: only time and position, nothing else.
Usage: record.py SECONDS OUT.tsv   (lines: t_seconds x y, global layout pixels; ~100 Hz)"""
import json, subprocess, sys, time

dur, out = float(sys.argv[1]), sys.argv[2]
t0 = time.monotonic()
nxt = t0
with open(out, "w") as f:
    while (now := time.monotonic()) - t0 < dur:
        r = subprocess.run(["mmsg", "get", "cursorpos"], capture_output=True, text=True)
        try:
            p = json.loads(r.stdout)
            f.write(f"{now - t0:.4f} {p['x']:.1f} {p['y']:.1f}\n")
        except (ValueError, KeyError):
            pass
        nxt += 0.01
        time.sleep(max(0, nxt - time.monotonic()))
