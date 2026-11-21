#!/usr/bin/env python3
"""Waybar tailnet host dots + tailnet status table tooltip.

Usage: host-status.py [--notify] <host> [<host> ...]
--notify: show the tooltip once as a notification (for click actions) and exit.
Shows only the current state reported by tailscaled; nothing is kept between checks.
Dot: green = online, red = offline, gray = tailscale down / host not on tailnet.
Online hosts listed in PROBES show a number instead of the green dot (robots: battery
SoC, gpu-server: VRAM usage %), read over ssh at most once per PROBE_INTERVAL and cached
in PROBE_CACHE in between (shared by all instances, survives waybar restarts).
"""

import http.client
import json
import os
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from html import escape

INTERVAL = 5
TS_SOCK = "/var/run/tailscale/tailscaled.sock"
COLORS = {"up": "#50fa7b", "down": "#ff5555", "noroute": "#808080"}

PROBE_INTERVAL = 30
PROBE_CACHE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "waybar-host-battery.json")
# Snapshot the robot's own /lf/bmsstate subscriber keeps on disk. Reading it
# costs nothing; running `ros2 topic echo` per poll burned whole cores there
# and left a _ros2_daemon behind.
BATTERY_CMD = "cat ~/.cache/g1_state.json"
BATTERY_MAX_AGE = 120  # ignore a snapshot the robot stopped updating
# One ssh round trip of cheap reads: two nvidia-smi queries plus /proc and df.
GPU_CMD = (
    "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw"
    " --format=csv,noheader,nounits 2>&1 | head -8; echo @;"
    " nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null |"
    " head -12 | while IFS=', ' read -r p m; do echo \"$m $(ps -o user=,comm= -p $p)\"; done; echo @;"
    " nproc; cat /proc/loadavg /proc/uptime;"
    " echo \"cpu $(head -1 /proc/stat)\"; sleep 0.5; echo \"cpu $(head -1 /proc/stat)\";"
    " grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo; df -P / | tail -1"
)
online = set()  # hosts tailscale currently reports online
probed = {}  # host -> last probe result
probe_t = {}  # host -> time of that result

notify = "--notify" in sys.argv
hosts = [a for a in sys.argv[1:] if a != "--notify"]


class TailscaleConn(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(2)
        self.sock.connect(TS_SOCK)


def ts_status():
    try:
        c = TailscaleConn("local-tailscaled.sock")
        c.request("GET", "/localapi/v0/status")
        d = json.loads(c.getresponse().read())
        c.close()
        return d
    except (OSError, ValueError, http.client.HTTPException):
        return None


def short(p):
    return (p.get("DNSName") or p.get("HostName") or "?").split(".")[0]


def ipv4(p):
    return next((a for a in p.get("TailscaleIPs") or [] if "." in a), "")


def ago(ts):
    try:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return ""
    if t.year < 2000:
        return ""
    s = int((datetime.now(timezone.utc) - t).total_seconds())
    for unit, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if s >= n:
            return f"{s // n}{unit} ago"
    return f"{s}s ago"


def table(d, highlight):
    rows = []
    for p in [d["Self"], *(d.get("Peer") or {}).values()]:
        online = bool(p.get("Online"))
        status = "online" if online else f"offline {ago(p.get('LastSeen'))}".strip()
        if p is d["Self"]:
            status += " (this)"
        rows.append((online, short(p), ipv4(p), p.get("OS", ""), status))
    rows.sort(key=lambda r: (not r[0], r[1]))

    w_name = max(len(r[1]) for r in rows)
    w_ip = max(len(r[2]) for r in rows)
    w_os = max(len(r[3]) for r in rows)
    lines = []
    for online, name, ip, os_, status in rows:
        line = escape(f"{name:<{w_name}}  {ip:<{w_ip}}  {os_:<{w_os}}  {status}")
        if name in highlight:
            line = f"<b>{line}</b>"
        color = COLORS["up" if online else "down"]
        lines.append(f"<span color='{color}'>●</span> {line}")
    return "<tt>" + "\n".join(lines) + "</tt>"


def cache_load():
    """host -> {"v": probe result or None if the last read failed, "t": read time}"""
    try:
        with open(PROBE_CACHE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def cache_store(host, value, t):
    d = cache_load()
    d[host] = {"v": value, "t": t}
    tmp = f"{PROBE_CACHE}.{os.getpid()}.{host}"
    try:
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, PROBE_CACHE)
    except OSError:
        pass


def cache_apply(host, entry):
    v = entry.get("v", entry.get("soc"))  # "soc": battery-only cache written before PROBES
    if v is not None:
        probed[host] = v
        probe_t[host] = entry.get("t")
    else:
        probed.pop(host, None)


def parse_battery(out):
    state = json.loads(out)
    if abs(time.time() - state["written_at"]) > BATTERY_MAX_AGE:
        return None
    return int(state["bms"]["soc"])


def num(x):
    try:
        return float(x)
    except ValueError:
        return None


def parse_gpu(out):
    gpu, procs, sys_ = (out.split("@\n") + ["", ""])[:3]
    if not sys_.strip():
        raise ValueError("no output")
    r = {"gpus": [], "gpu_err": "", "procs": []}
    for line in gpu.splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) == 6 and num(f[1]) is not None:
            r["gpus"].append([f[0]] + [num(x) for x in f[1:]])
        elif line.strip() and not r["gpu_err"]:
            r["gpu_err"] = line.strip()
    for line in procs.splitlines():
        f = line.split()
        if f and num(f[0]) is not None:
            r["procs"].append([num(f[0]), f[1] if len(f) > 1 else "?", " ".join(f[2:]) or "?"])
    mem = {}
    for line in sys_.splitlines():
        f = line.split()
        if len(f) > 9 and f[0] == f[1] == "cpu":
            r.setdefault("stat", []).append([int(x) for x in f[2:10]])
        elif len(f) == 1 and f[0].isdigit():
            r["cores"] = int(f[0])
        elif len(f) == 5 and "/" in f[3]:
            r["load"] = f[:3]
        elif len(f) == 2 and num(f[0]) is not None:
            r["uptime"] = num(f[0])
        elif len(f) == 3 and f[0].endswith(":"):
            mem[f[0][:-1]] = int(f[1]) * 1024
        elif len(f) == 6 and f[4].endswith("%"):
            r["disk"] = [int(f[2]) * 1024, (int(f[2]) + int(f[3])) * 1024]  # df's Use%
    if "MemTotal" in mem:
        r["mem"] = [mem["MemTotal"] - mem.get("MemAvailable", 0), mem["MemTotal"]]
        r["swap"] = [mem.get("SwapTotal", 0) - mem.get("SwapFree", 0), mem.get("SwapTotal", 0)]
    return r


def cpu_fill(v):
    """CPU busy % over the 0.5 s between two /proc/stat reads; None (plain dot) if unreadable"""
    if len(v.get("stat", [])) < 2:
        return None
    a, b = v["stat"][:2]
    total = sum(b) - sum(a)
    idle = (b[3] + b[4]) - (a[3] + a[4])  # idle + iowait
    return round(100 * (total - idle) / total) if total > 0 else None


def vram_fill(v):
    """VRAM used % summed over all GPUs; None (plain dot) if no GPU is readable"""
    total = sum(g[2] for g in v.get("gpus", []))
    used = sum(g[1] for g in v.get("gpus", []))
    return round(100 * used / total) if total > 0 else None


def gib(b):
    return f"{b / 2**30:.1f}"


def gpu_table(v):
    rows = []
    if v["gpus"]:
        rows.append("GPU  memory (GiB)       util  temp  power")
        for i, (name, used, total, util, temp, power) in enumerate(v["gpus"]):
            pct = f"{100 * used / total:.0f}%" if total else "?"
            m = f"{used / 1024:.1f}/{total / 1024:.1f} {pct}"
            u = f"{util:.0f}%" if util is not None else "-"
            t = f"{temp:.0f}°C" if temp is not None else "-"
            w = f"{power:.0f}W" if power is not None else "-"
            rows.append(f"{i:<3}  {m:<17}  {u:>4}  {t:>4}  {w:>5}  {name}")
        for mib, user, cmd in sorted(v["procs"], reverse=True):
            rows.append(f"     {mib / 1024:5.1f} GiB  {user:<10} {cmd}")
    else:
        rows.append(f"GPU  {v['gpu_err'] or 'no GPUs reported'}")
    rows.append("")
    cpu = cpu_fill(v)
    if cpu is not None:
        rows.append(f"CPU now {cpu}%")
    if "load" in v:
        cores = v.get("cores")
        if cores:  # load average as a share of all cores: 100% = every core busy
            pct = [100 * float(x) / cores for x in v["load"]]
            pct = " ".join(f"{x:.1f}%" if x < 10 else f"{x:.0f}%" for x in pct)
            rows.append(f"CPU     {pct}  (1/5/15m load, {cores} cores)")
        else:
            rows.append(f"load    {' '.join(v['load'])}")
    for key, label in (("mem", "RAM"), ("swap", "swap"), ("disk", "disk /")):
        if key in v and v[key][1]:
            used, total = v[key]
            rows.append(f"{label:<7} {gib(used)}/{gib(total)} GiB  {100 * used / total:.0f}%")
    if "uptime" in v:
        s = int(v["uptime"])
        rows.append(f"uptime  {s // 86400}d {s % 86400 // 3600}h {s % 3600 // 60}m")
    return "<tt>" + escape("\n".join(rows)) + "</tt>"


# tailnet host -> (ssh alias, remote command, parser, text shown instead of the dot,
#                  extra tooltip block)
PROBES = {
    "unitree-g1": ("robot1-ssh", BATTERY_CMD, parse_battery, str, None),
    "unitree-r1": ("robot2-ssh", BATTERY_CMD, parse_battery, str, None),
    "gpu-server": ("gpu-server-ssh", GPU_CMD, parse_gpu, vram_fill, gpu_table),
}


def probe_loop(host):
    alias, cmd, parse = PROBES[host][:3]
    while True:
        if host not in online:
            time.sleep(1)
            continue
        entry = cache_load().get(host)
        if not isinstance(entry, dict):
            entry = {}
        cache_apply(host, entry)
        age = time.time() - entry.get("t", 0) if isinstance(entry.get("t"), (int, float)) else None
        if age is not None and 0 <= age < PROBE_INTERVAL:
            time.sleep(1)
            continue
        try:
            out = subprocess.run(
                ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias, cmd],
                capture_output=True, text=True, timeout=10,
            ).stdout
            value = parse(out)
        except (subprocess.TimeoutExpired, OSError, ValueError, KeyError, TypeError, IndexError):
            value = None
        t = time.time()
        cache_store(host, value, t)
        cache_apply(host, {"v": value, "t": t})


def tick():
    d = ts_status()
    running = d is not None and d.get("BackendState") == "Running"
    peers = {short(p): p for p in (d.get("Peer") or {}).values()} if running else {}

    dots, header, extra = [], [], []
    for h in hosts:
        p = peers.get(h)
        if p is None:
            state, desc = "noroute", "not on tailnet" if running else "tailscale down"
        elif p.get("Online"):
            state, desc = "up", f"online ({ipv4(p)})"
        else:
            state, desc = "down", f"offline {ago(p.get('LastSeen'))} ({ipv4(p)})"
        if state == "up":
            online.add(h)
        else:
            online.discard(h)
            probed.pop(h, None)
        mark = "●"
        v = probed.get(h)
        if v is not None:
            text = PROBES[h][3](v)
            if text is not None:
                mark = str(text)
            if PROBES[h][2] is parse_battery:
                desc += f", battery {mark}%"
            else:
                if isinstance(text, int):
                    desc += f", VRAM {mark}%"
                if isinstance(probe_t.get(h), (int, float)):
                    desc += f", read {int(time.time() - probe_t[h])}s ago"
                extra.append(PROBES[h][4](v))
        dots.append(f"<span color='{COLORS[state]}'>{mark}</span>")
        header.append(f"<span color='{COLORS[state]}'>●</span> <b>{escape(h)}</b>: {escape(desc)}")

    if running:
        body = table(d, set(hosts))
    elif d is None:
        body = "tailscale unavailable"
    else:
        body = f"tailscale: {escape(str(d.get('BackendState')))}"

    return {"text": "  ".join(dots), "tooltip": "\n\n".join(["\n".join(header), *extra, body])}


# start from the cached readings so the first output already shows them
for h, entry in cache_load().items():
    if isinstance(entry, dict):
        cache_apply(h, entry)

if notify:
    subprocess.run(["notify-send", "-r", "47120", "-a", "tailnet", "Tailnet", tick()["tooltip"]])
    sys.exit()

for h in hosts:
    if h in PROBES:
        threading.Thread(target=probe_loop, args=(h,), daemon=True).start()

while True:
    print(json.dumps(tick()), flush=True)
    time.sleep(INTERVAL)
