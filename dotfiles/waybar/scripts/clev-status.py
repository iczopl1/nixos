#!/usr/bin/env python3
"""Waybar clev pill: opens the goal prompt and shows what a run is doing.

Usage: clev-status.py              stream JSON lines for waybar
       clev-status.py --click L|R  act on a click, by the current state
       clev-status.py --prompt     the goal prompt, for SUPER+SHIFT+D

Icon only, one per state (CSS class): ✦ idle (click to type a goal), a spinning
◐ running (the goal is in the tooltip; frames only while it runs), ? confirm (a step waits for SUPER+Y / SUPER+N).
  left click:  idle -> goal prompt (clev-goal), confirm -> allow
  right click: running -> stop the run (clev stop), confirm -> deny

No polling: blocks on inotify over $XDG_RUNTIME_DIR/clev (driver.pid,
goal and the answer FIFO come and go there) and on a pidfd of the running
clev-goal, so a run that dies without cleaning up still ends the pill.
Colors come from colors.css, so wal re-theming follows.
"""

import ctypes
import json
import os
import re
import select
import subprocess
import sys
from html import escape

RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "clev")
DRIVER_PID = os.path.join(RUN, "driver.pid")
GOAL = os.path.join(RUN, "goal")  # written by clev-goal for the run's lifetime
ANSWER_FIFO = os.path.join(RUN, "answer")
COLORS_CSS = os.path.expanduser("~/.config/waybar/colors.css")
FALLBACK = {f"flow-{i}": c for i, c in enumerate(
    ["#4fb3ff", "#5ab0fb", "#6faef7", "#80aaf3", "#8fa8ef", "#9fa6eb",
     "#afa5e7", "#bfa3e3", "#cfa1df", "#df9fdb", "#ef9cd7", "#ff9ad3"], 1)}
FALLBACK.update({"text": "#ffd7e3", "overlay2": "#8c96b8"})
ICON_FONT = "DejaVu Sans Mono"
SPIN = "◐◓◑◒"  # one quarter turn per frame
FRAME_S = 0.15

IN_CLOSE_WRITE, IN_MOVED_FROM, IN_MOVED_TO = 0x8, 0x40, 0x80
IN_CREATE, IN_DELETE, IN_DELETE_SELF = 0x100, 0x200, 0x400


def palette():
    c = dict(FALLBACK)
    try:
        with open(COLORS_CSS) as f:
            c.update(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", f.read()))
    except OSError:
        pass
    return c


def driver_pid():
    """pid of the running clev-goal, or None (a stale pid file is no run)."""
    try:
        with open(DRIVER_PID) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return pid if b"clev-goal" in f.read() else None
    except (OSError, ValueError):
        return None


def state():
    pid = driver_pid()
    if os.path.exists(ANSWER_FIFO):
        return "confirm", pid
    return ("running" if pid else "idle"), pid


def goal_text():
    try:
        with open(GOAL) as f:
            return " ".join(f.read().split())
    except OSError:
        return ""


def icon(glyph, color):
    """Icon only; one monospace font with every glyph keeps the pill one width."""
    return f"<span weight='bold' font_family='{ICON_FONT}' size='large' color='{color}'>{glyph}</span>"


def render(st, c, frame=0):
    if st == "confirm":
        text = icon("?", c["flow-12"])
        tip = "Clev AI is waiting on you\nleft click / SUPER+Y  allow\nright click / SUPER+N  deny\n60 s without an answer = deny"
    elif st == "running":
        goal = goal_text()
        # the glyph turns while its color walks the flow ramp and back
        step = frame % 22
        text = icon(SPIN[frame % len(SPIN)], c[f"flow-{1 + (step if step < 12 else 22 - step)}"])
        tip = (f"Clev AI: {escape(goal)}\n" if goal else "Clev AI is working\n") + \
            "right click / SUPER+SHIFT+Esc  stop"
    else:
        text = icon("✦", c["flow-12"])
        tip = "Clev AI: what should I help with?\nleft click / SUPER+SHIFT+D  type a goal"
    return json.dumps({"text": text, "class": st, "alt": st, "tooltip": tip})


def watch():
    os.makedirs(RUN, mode=0o700, exist_ok=True)
    libc = ctypes.CDLL(None, use_errno=True)
    ino = libc.inotify_init1(os.O_CLOEXEC)
    mask = IN_CREATE | IN_DELETE | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE_SELF
    if ino < 0 or libc.inotify_add_watch(ino, RUN.encode(), mask) < 0:
        sys.exit(f"clev-status: inotify: {os.strerror(ctypes.get_errno())}")
    c, last, pidfd, watched, frame = palette(), None, None, None, 0
    while True:
        st, pid = state()
        if pid != watched:  # follow the run's process: its exit wakes us even without a file event
            if pidfd is not None:
                os.close(pidfd)
            pidfd, watched = None, pid
            if pid:
                try:
                    pidfd = os.pidfd_open(pid)
                except OSError:
                    pass
        line = render(st, c, frame)
        if line != last:
            print(line, flush=True)
            last = line
        ready, _, _ = select.select([ino] + ([pidfd] if pidfd is not None else []), [], [],
                                   FRAME_S if st == "running" else None)
        frame = frame + 1 if st == "running" else 0
        if ino in ready:
            buf = os.read(ino, 4096)
            if int.from_bytes(buf[4:8], sys.byteorder) & IN_DELETE_SELF:
                os.execv(sys.executable, [sys.executable] + sys.argv)  # run dir removed: start over
            c = palette()  # cheap; picks up a wal re-theme on the next event


PROMPT_W = 440
PROMPT_GAP = 6  # px below the bar
PILL_X = os.path.expanduser("~/.cache/clev/pill-x")  # last clicked x on the monitor
DEFAULT_PILL_X = 244  # where the pill sits today, until the first click
ICON_X = 18  # the prompt's ✦ from its left edge (border + padding)


def prompt_theme(c, x, y):
    """rofi drawn as one input pill in the bar's colors, top-left at (x, y)."""
    base, hi, text = c.get("base", "#293c47"), c["flow-12"], c["text"]
    return f"""
* {{ background-color: transparent; text-color: {text}; font: "DejaVu Sans 11"; }}
window {{ location: north west; anchor: north west; x-offset: {x}px; y-offset: {y}px;
  width: {PROMPT_W}px; border: 2px solid; border-radius: 12px;
  border-color: {hi};
  background-color: {base}f2; padding: 4px 10px; }}
mainbox {{ children: [ inputbar ]; padding: 0; spacing: 0; }}
inputbar {{ children: [ prompt, entry ]; spacing: 10px; padding: 6px 2px; }}
prompt {{ text-color: {hi}; }}
entry {{ placeholder: "What should I help with?"; placeholder-color: {c["overlay2"]};
  cursor: text; }}
"""


def prompt_at(clicked):
    """Top-left for the prompt: its ✦ right under the pill's ✦, kept on the
    monitor. A click gives the pill's x (the cursor is on it) and is remembered,
    so the hotkey opens the prompt in the same place. rofi's layer already starts
    below the bar's exclusive zone, so y is just the gap."""
    try:
        run = lambda *a: subprocess.run(a, capture_output=True, text=True).stdout
        mango = bool(os.environ.get("MANGO_INSTANCE_SIGNATURE"))
        if mango:  # mango reports logical sizes, so scale is already applied
            mon = next(dict(m, scale=1) for m in json.loads(run("mmsg", "get", "all-monitors"))["monitors"]
                       if m.get("active"))
        else:
            mon = next(m for m in json.loads(run("hyprctl", "monitors", "-j")) if m.get("focused"))
        if clicked:
            cx = (json.loads(run("mmsg", "get", "cursorpos"))["x"] if mango
                  else int(run("hyprctl", "cursorpos").split(",")[0]))
            px = int(cx) - mon["x"]
            os.makedirs(os.path.dirname(PILL_X), exist_ok=True)
            with open(PILL_X, "w") as f:
                f.write(str(px))
        else:
            try:
                with open(PILL_X) as f:
                    px = int(f.read())
            except (OSError, ValueError):
                px = DEFAULT_PILL_X
        w = round(mon["width"] / mon["scale"])
        return min(max(px - ICON_X, 8), w - PROMPT_W - 8), PROMPT_GAP
    except (OSError, ValueError, KeyError, StopIteration):
        return 8, PROMPT_GAP


def ask_goal(clicked):
    x, y = prompt_at(clicked)
    theme = os.path.join(RUN, "prompt.rasi")  # a whole theme: nothing leaks in from config.rasi
    with open(theme, "w") as f:
        f.write(prompt_theme(palette(), x, y))
    r = subprocess.run(["rofi", "-dmenu", "-p", "✦", "-theme", theme],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def start(clicked):
    """Ask for a goal under the pill and hand it to clev-goal (asked here,
    not by clev-goal, so it can sit under the pill)."""
    goal = ask_goal(clicked)
    if goal:
        subprocess.Popen(["clev-goal", goal], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def click(button):
    st, _ = state()
    if button == "L" and st == "idle":
        start(clicked=True)
    elif st == "confirm":
        subprocess.run(["clev", "answer", "y" if button == "L" else "n"])
    elif button == "R" and st == "running":
        subprocess.run(["clev", "stop"])


def hotkey():
    """SUPER+SHIFT+D: the same prompt, where the pill is."""
    if state()[0] == "idle":
        start(clicked=False)
    else:
        subprocess.run(["notify-send", "-a", "clev", "clev busy",
                        "A goal is already running (SUPER+SHIFT+Escape stops it)"])


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--click":
        click(sys.argv[2])
    elif sys.argv[1:] == ["--prompt"]:
        hotkey()
    else:
        watch()
