#!/usr/bin/env python3
"""Waybar Claude Code activity: what every running claude session is doing.

Usage: claude-status.py             stream JSON lines for waybar
       claude-status.py --focus     focus the terminal of the session that most
                                    wants attention (waiting > working > done)

Reads the per-session files the `waybar-status` Claude Code mod writes to
$XDG_RUNTIME_DIR/claude-status/<session>.json and drops files whose claude
process is gone. Colors come from colors.css, so wal re-theming follows.

Icons only, one per session, most urgent first: a spinning, breathing glyph
while working, ◆ waiting on you (permission / an answer), ✓ done (✗ failed or
interrupted) for a moment, ✻ idle, ◌ a claude process the mod isn't loaded in.
The pill's CSS class is the most urgent session's state: working, waiting,
done, idle, unknown, none.
"""

import json
import math
import os
import re
import subprocess
import sys
import time
from html import escape

DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "claude-status")
COLORS_CSS = os.path.expanduser("~/.config/waybar/colors.css")
STALE_S = 45  # no heartbeat this long and no pid to check: gone
FAST, SLOW = 0.2, 1.0  # frame time while something spins / while quiet
DATA_S = 1.0  # re-read the status files at most this often; frames between redraw the cache
PROC_S = 3.0  # re-scan /proc for claude processes the mod is not in

SPINNER = "·✢✳✶✻✽✻✶✳✢"  # Claude Code's own spinner glyphs, bounced
RANK = {"waiting": 0, "working": 1, "done": 2, "idle": 3, "unknown": 4}
DOT = {"waiting": "◆", "working": "●", "done": "✓", "idle": "○", "unknown": "◌"}  # tooltip marks
ICON_FONT = "DejaVu Sans Mono"  # monospace with every glyph below: the pill keeps one width while spinning
CLAUDE_COMMS = {"claude", ".claude-wrapped"}  # the nix wrapper renames the process
FALLBACK = {"flow-1": "#4fb3ff", "flow-3": "#6faef7", "flow-7": "#afa5e7",
            "flow-10": "#df9fdb", "flow-12": "#ff9ad3", "text": "#ffd7e3",
            "overlay2": "#8c96b8", "green": "#8faaef"}


def palette():
    c = dict(FALLBACK)
    try:
        with open(COLORS_CSS) as f:
            c.update(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", f.read()))
    except OSError:
        pass
    return c


def mix(a, b, t):
    pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(pa, pb))


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def claude_procs():
    """(pid, cwd) of every top-level claude process: one per session."""
    procs = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                comm, rest = f.read().split("(", 1)[1].rsplit(")", 1)
            procs[int(d)] = (comm, int(rest.split()[1]))
        except (OSError, ValueError, IndexError):
            continue
    is_claude = lambda pid: procs.get(pid, ("", 0))[0] in CLAUDE_COMMS
    out = []
    for pid, (comm, ppid) in procs.items():
        if comm in CLAUDE_COMMS and not is_claude(ppid):  # a claude's own child claude is no session
            try:
                cwd = os.readlink(f"/proc/{pid}/cwd")
            except OSError:
                cwd = ""
            out.append((pid, cwd))
    return out


def sessions(procs=None):
    out = []
    try:
        names = os.listdir(DIR)
    except OSError:
        return out
    now = time.time()
    for n in names:
        if not n.endswith(".json"):
            continue
        p = os.path.join(DIR, n)
        try:
            with open(p) as f:
                s = json.load(f)
        except (OSError, ValueError):
            continue  # mid-write; next frame reads it
        pid = s.get("pid")
        gone = s.get("state") == "ended" or (
            alive(pid) is False if isinstance(pid, int)
            else now - s.get("updated", 0) / 1000 > STALE_S)
        if gone:
            try:
                os.remove(p)
            except OSError:
                pass
            continue
        out.append(s)
    # claude processes the mod is not running in (started before it was set up)
    reported = {s.get("pid") for s in out}
    for pid, cwd in claude_procs() if procs is None else procs:
        if pid not in reported:
            out.append({"session": f"pid-{pid}", "pid": pid, "cwd": cwd, "state": "unknown", "since": 0})
    out.sort(key=lambda s: (RANK.get(s.get("state"), 9), -s.get("since", 0)))
    return out


def dur(ms):
    s = max(0, int(ms // 1000))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{s % 3600 // 60:02d}m"


def name(s):
    if s.get("title"):
        return s["title"]
    return os.path.basename(s.get("cwd", "").rstrip("/")) or "~"


def tooltip(ss, c, now_ms):
    if not ss:
        return "No Claude sessions running"
    color = {"waiting": c["flow-12"], "working": c["flow-1"], "done": c["green"], "idle": c["overlay2"], "unknown": c["overlay2"]}
    rows = []
    for s in ss:
        st = s.get("state", "idle")
        head = (f"<span color='{color.get(st, c['text'])}'>{DOT.get(st, '?')}</span> "
                f"<b>{escape(name(s))}</b>  <span color='{c['overlay2']}'>{escape(st)}")
        if st in ("working", "waiting") and s.get("turnStart"):
            head += f" · {dur(now_ms - s['turnStart'])}"
        elif st in ("done", "idle") and s.get("lastDurationMs") is not None:
            head += f" · last turn {dur(s['lastDurationMs'])}"
            if s.get("lastReason") not in (None, "answer"):
                head += f" ({escape(s['lastReason'])})"
        elif st == "unknown":
            head += " · not reporting, restart it to load the mod"
        head += "</span>"
        lines = [head]
        if st in ("working", "waiting"):
            what = " ".join(x for x in (s.get("tool"), s.get("detail")) if x)
            if what:
                lines.append(f"    ⤷ {escape(what)}")
            extra = [f"{s.get('tools', 0)} tool calls"]
            if s.get("agents"):
                extra.append(f"{s['agents']} subagent{'s' if s['agents'] > 1 else ''}")
            lines.append(f"    <span color='{c['overlay2']}'>{' · '.join(extra)}</span>")
        if s.get("prompt"):
            lines.append(f"    <i><span color='{c['overlay2']}'>“{escape(s['prompt'])}”</span></i>")
        cwd = s.get("cwd", "").replace(os.path.expanduser("~"), "~", 1)
        model = s.get("model") or ""
        lines.append(f"    <span size='small' color='{c['overlay2']}'>{escape(cwd)}  {escape(model)}</span>")
        rows.append("\n".join(lines))
    hint = f"\n\n<span size='small' color='{c['overlay2']}'>click: jump to the session that needs you</span>"
    return "\n\n".join(rows) + hint


def glyph(s, i, frame, c):
    """One icon per session, all in ICON_FONT so every glyph has the same advance."""
    return f"<span font_family='{ICON_FONT}'>{_glyph(s, i, frame, c)}</span>"


def _glyph(s, i, frame, c):
    """A working session spins and breathes, offset by its slot."""
    st = s.get("state", "idle")
    if st == "working":
        f = frame + i * 3
        breath = (1 + math.sin(f / 4)) / 2
        return f"<span color='{mix(c['flow-10'], c['text'], breath)}'>{SPINNER[f % len(SPINNER)]}</span>"
    if st == "waiting":
        return f"<span color='{c['flow-12']}'><b>◆</b></span>"
    if st == "done":
        failed = s.get("lastReason") not in (None, "answer")
        return f"<span color='{c['flow-12'] if failed else c['green']}'>{'✗' if failed else '✓'}</span>"
    if st == "unknown":
        return f"<span color='{c['overlay2']}'>◌</span>"
    return f"<span color='{c['overlay2']}'>✻</span>"


def render(ss, frame, c, tip):
    if not ss:
        return {"text": "", "class": "none", "tooltip": tip}, False
    st = ss[0].get("state", "idle")  # the most urgent session sets the pill's mood
    text = " ".join(glyph(s, i, frame, c) for i, s in enumerate(ss))
    moving = any(s.get("state") == "working" for s in ss)
    return {"text": text, "class": st, "tooltip": tip, "alt": st}, moving


def focus():
    ss = sessions()
    if not ss or not isinstance(ss[0].get("pid"), int):
        return
    target = ss[0]
    try:
        clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
    except (OSError, ValueError):
        return
    by_pid = {}
    for cl in clients:
        by_pid.setdefault(cl.get("pid"), []).append(cl)
    pid = target["pid"]
    while pid > 1 and pid not in by_pid:  # walk up to the terminal that owns it
        try:
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            return
    wins = by_pid.get(pid)
    if not wins:
        return
    # one terminal process may own many windows: prefer the one titled after the session
    want = name(target).lower()
    win = next((w for w in wins if want and want in w.get("title", "").lower()), wins[0])
    subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{win['address']}"], capture_output=True)


if __name__ == "__main__":
    if "--focus" in sys.argv:
        focus()
        sys.exit()
    # Only the spinner moves between data reads: frames re-render the cached
    # sessions, and the files, /proc and the tooltip are touched once per
    # DATA_S / PROC_S at most.
    parent = os.getppid()  # waybar; reparented means it is gone
    frame, colors, last = 0, palette(), None
    data_at = procs_at = colors_at = float("-inf")
    while True:
        now = time.monotonic()
        if now - colors_at > 5:
            colors, colors_at = palette(), now
        if now - procs_at >= PROC_S:
            if os.getppid() != parent:
                sys.exit()
            procs, procs_at = claude_procs(), now
        if now - data_at >= DATA_S:
            ss, data_at = sessions(procs), now
            tip = tooltip(ss, colors, time.time() * 1000)
        out, moving = render(ss, frame, colors, tip)
        line = json.dumps(out)
        if line != last:
            print(line, flush=True)
            last = line
        frame += 1
        time.sleep(FAST if moving else SLOW)
