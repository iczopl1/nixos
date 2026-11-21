#!/usr/bin/env python3
"""Waybar mic-in-use indicator: shown only while something records from a mic.

A capture stream counts when it is running and linked to a real input device
(Audio/Source), so cava, peak meters and anything else recording a sink's
monitor are ignored. Follows the PipeWire graph from one long-lived
`pw-dump --monitor`; no polling. Empty text hides the module.

Classes: live (recording, mic on), muted (recording, mic muted).
"""

import ctypes
import json
import os
import select
import signal
import subprocess
import sys
import time
from html import escape

PARENT_CHECK_S = 5  # how often a quiet loop checks that waybar is still there
SETTLE_S = 0.15  # PipeWire changes come in bursts: wait for the burst to end
ICON_LIVE, ICON_MUTED = "", ""  # Font Awesome microphone / microphone-slash


def muted(node):
    for p in (node.get("info", {}).get("params", {}) or {}).get("Props", []) or []:
        if "mute" in p:
            return bool(p["mute"])
    return False


def recorders(objs):
    """[(app, mic description, mic muted)] for every running capture from a mic."""
    nodes = {o["id"]: o for o in objs if o.get("type") == "PipeWire:Interface:Node"}
    feeds = {}  # stream node id -> ids of the nodes feeding it
    for o in objs:
        if o.get("type") == "PipeWire:Interface:Link":
            i = o.get("info", {})
            feeds.setdefault(i.get("input-node-id"), set()).add(i.get("output-node-id"))
    out = []
    for nid, n in nodes.items():
        info = n.get("info", {})
        props = info.get("props", {})
        if props.get("media.class") != "Stream/Input/Audio" or info.get("state") != "running":
            continue
        if props.get("stream.capture.sink") or props.get("stream.monitor"):
            continue
        mics = [nodes[s] for s in feeds.get(nid, ()) if s in nodes
                and nodes[s].get("info", {}).get("props", {}).get("media.class") in ("Audio/Source", "Audio/Duplex")]
        if not mics:
            continue  # unlinked, or fed by a sink's monitor
        app = props.get("application.name") or props.get("application.process.binary") or props.get("node.name") or "?"
        for m in mics:
            mp = m["info"]["props"]
            out.append((app, mp.get("node.description") or mp.get("node.name") or "mic", muted(m)))
    return out


def render(recs):
    if not recs:
        return {"text": "", "class": "idle", "tooltip": ""}
    all_muted = all(m for _, _, m in recs)
    apps = sorted({a for a, _, _ in recs})
    lines = [f"<b>{'Mic muted' if all_muted else 'Mic live'}</b>"]
    for app, mic, m in sorted(set(recs)):
        lines.append(f"{ICON_MUTED if m else ICON_LIVE}  {escape(app)}  <small>{escape(mic)}</small>")
    lines.append("\n<small>click: mute / unmute   right-click: recording mixer</small>")
    return {
        "text": ICON_MUTED if all_muted else ICON_LIVE,
        "class": "muted" if all_muted else "live",
        "alt": "muted" if all_muted else "live",
        "tooltip": "\n".join(lines),
        "percentage": len(apps),
    }


def die_with_parent():
    """In the child: take a SIGTERM when this script dies, however it dies."""
    ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


def merge(old, new):
    """An update carries the object's changed parts; keep the rest."""
    if not isinstance(old, dict) or not isinstance(new, dict):
        return new
    out = dict(old)
    for k, v in new.items():
        out[k] = merge(old.get(k), v)
    return out


def apply(objs, batch):
    """Fold one `pw-dump --monitor` batch into {id: object}; info null removes."""
    for o in batch:
        if not isinstance(o, dict) or "id" not in o:
            continue
        if o.get("info", 0) is None:
            objs.pop(o["id"], None)
        else:
            objs[o["id"]] = merge(objs.get(o["id"]), o)


def main():
    # One long-lived `pw-dump --monitor`: its first batch is the whole graph,
    # each later one the objects that changed. State is built from the stream
    # alone; running pw-dump per change would itself be a change (every
    # connection is a new PipeWire client) and feed back into a busy loop.
    dec = json.JSONDecoder()
    parent = os.getppid()  # waybar; reparented means it is gone
    last = None
    while True:
        objs, buf = {}, ""
        mon = subprocess.Popen(["pw-dump", "--monitor", "--no-colors"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               preexec_fn=die_with_parent)
        fd = mon.stdout.fileno()
        dirty = False
        while True:
            ready, _, _ = select.select([fd], [], [], SETTLE_S if dirty else PARENT_CHECK_S)
            if os.getppid() != parent:
                mon.kill()
                sys.exit()
            if ready:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break  # pw-dump exited (PipeWire restarted)
                buf += chunk.decode("utf-8", "replace")
                while True:
                    start = buf.find("[")
                    if start < 0:
                        buf = ""
                        break
                    try:
                        batch, end = dec.raw_decode(buf, start)
                    except ValueError:
                        buf = buf[start:]  # incomplete: wait for more
                        break
                    apply(objs, batch if isinstance(batch, list) else [])
                    buf = buf[end:]
                    dirty = True
                continue
            if not dirty:
                continue  # just the parent check's wakeup
            # a burst of changes has settled: redraw if what we show changed
            line = json.dumps(render(recorders(list(objs.values()))))
            if line != last:
                print(line, flush=True)
                last = line
            dirty = False
        mon.kill()
        mon.wait()
        time.sleep(2)


if __name__ == "__main__":
    main()
