#!/usr/bin/env python3
"""Now-playing stream for the bar's music chip, with synced lyrics.

Prints one JSON line {"text","tooltip","class"} each time the output changes.
Same shape as waybar's now-playing.sh. While a synced lyric line is showing,
"text" is that line and "class" also holds "lyric"; otherwise "text" is
"artist — title" as before. "track" names the song so the bar can tell a
track change from a lyric change.

Sources: playerctl (MPRIS) first, then the bgm mpv socket. A YouTube video
with captions on shows the caption: the "Bar subtitles" add-on (bar/subs/)
POSTs it to 127.0.0.1:47613, served by this script. Lyrics: a local
.lrc file next to the mpv file, else lrclib.net (cached on disk, hits and
misses, keyed by artist|title).

Test without a player:  lyrics.py --test "Artist" "Title" [start_seconds]
"""

import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
BGM_SOCK = os.path.join(RUN, "bgm-mpv.sock")
BGM_PID = os.path.join(RUN, "bgm-mpv.pid")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "bar-lyrics")
MISS_RETRY = 7 * 86400   # a miss is retried after a week
SYNC_EVERY = 2.0         # re-read the player this often; interpolate between
TICK = 0.2
MAX_TRACK = 42
MAX_LYRIC = 48
LEAD = 0.3               # show a line a bit early; it reads better

LRC_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def clip(s, n):
    return s if len(s) <= n else s[: n - 3] + "..."


def parse_lrc(text):
    out = []
    for line in (text or "").splitlines():
        stamps = LRC_RE.findall(line)
        if not stamps:
            continue
        words = LRC_RE.sub("", line).strip()
        for m, s in stamps:
            out.append((int(m) * 60 + float(s), words))
    out.sort(key=lambda x: x[0])
    return out


# ---------- lyrics lookup ----------

_lyrics = {}       # key -> list of (t, line) or [] (none)
_pending = set()
_lock = threading.Lock()


def _key(artist, title):
    return (artist.strip().lower() + "|" + title.strip().lower())


def _cache_path(key):
    return os.path.join(CACHE, hashlib.sha1(key.encode()).hexdigest() + ".json")


def _fetch(artist, title, album, duration):
    q = {"artist_name": artist, "track_name": title}
    if album:
        q["album_name"] = album
    if duration:
        q["duration"] = str(int(round(duration)))
    ua = {"User-Agent": "quickshell-bar-lyrics/1.0"}
    try:
        req = urllib.request.Request("https://lrclib.net/api/get?" + urllib.parse.urlencode(q), headers=ua)
        with urllib.request.urlopen(req, timeout=5) as r:
            j = json.load(r)
            if j.get("syncedLyrics"):
                return j.get("syncedLyrics"), j.get("plainLyrics") or ""
    except Exception:
        pass
    # loose match: search, take the first hit that has synced lyrics
    try:
        q = {"artist_name": artist, "track_name": title}
        req = urllib.request.Request("https://lrclib.net/api/search?" + urllib.parse.urlencode(q), headers=ua)
        with urllib.request.urlopen(req, timeout=5) as r:
            for j in json.load(r):
                if j.get("syncedLyrics"):
                    return j["syncedLyrics"], j.get("plainLyrics") or ""
    except Exception:
        return None  # network trouble: not a real miss, do not cache
    return "", ""


def _load(key, artist, title, album, duration):
    path = _cache_path(key)
    try:
        with open(path) as f:
            c = json.load(f)
        if c.get("synced") or time.time() - c.get("at", 0) < MISS_RETRY:
            with _lock:
                _lyrics[key] = parse_lrc(c.get("synced", ""))
                _pending.discard(key)
            return
    except Exception:
        pass
    got = _fetch(artist, title, album, duration)
    if got is not None:
        os.makedirs(CACHE, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"artist": artist, "title": title, "synced": got[0], "plain": got[1], "at": time.time()}, f)
        os.replace(tmp, path)
    with _lock:
        _lyrics[key] = parse_lrc(got[0]) if got else []
        _pending.discard(key)


def lyrics_for(artist, title, album, duration, path):
    """Synced lines for this track, or None while loading / [] if none."""
    if not artist or not title:
        return []
    key = _key(artist, title)
    with _lock:
        if key in _lyrics:
            return _lyrics[key]
        if key in _pending:
            return None
    # local .lrc beside the file wins and needs no network
    if path and not path.startswith(("http://", "https://")):
        lrc = os.path.splitext(path)[0] + ".lrc"
        try:
            with open(lrc, errors="replace") as f:
                lines = parse_lrc(f.read())
            with _lock:
                _lyrics[key] = lines
            return lines
        except OSError:
            pass
    with _lock:
        _pending.add(key)
    threading.Thread(target=_load, args=(key, artist, title, album, duration), daemon=True).start()
    return None


# ---------- players ----------

def read_playerctl():
    fmt = "{{status}}\t{{playerName}}\t{{artist}}\t{{title}}\t{{album}}\t{{mpris:length}}\t{{position}}\t{{xesam:url}}"
    try:
        out = subprocess.run(["playerctl", "-a", "metadata", "--format", fmt],
                             capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return None
    # several players (e.g. two browsers): prefer one that is playing, else the first
    rows = [r.split("\t") for r in out.splitlines()]
    rows = [r for r in rows if len(r) >= 8 and (r[2] or r[3])]
    if not rows:
        return None
    parts = next((r for r in rows if r[0] == "Playing"), rows[0])
    status, player, artist, title, album, length, pos, url = parts[:8]
    def num(x):
        try:
            return float(x) / 1e6
        except ValueError:
            return 0.0
    path = urllib.parse.unquote(url[7:]) if url.startswith("file://") else ""
    return dict(status=status, player=player, artist=artist, title=title, album=album,
                length=num(length), pos=num(pos), path=path)


def _mpv(sock, prop):
    sock.sendall(json.dumps({"command": ["get_property", prop]}).encode() + b"\n")
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
    for line in buf.split(b"\n"):
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if "error" in j:   # skip event lines
            return j.get("data")
    return None


def read_bgm():
    try:
        with open(BGM_PID) as f:
            os.kill(int(f.read().strip()), 0)
    except Exception:
        return None
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(1)
        s.connect(BGM_SOCK)
        with s:
            path = _mpv(s, "path") or ""
            mtitle = _mpv(s, "media-title") or ""
            meta = _mpv(s, "metadata") or {}
            pause = _mpv(s, "pause")
            pos = _mpv(s, "time-pos") or 0.0
            length = _mpv(s, "duration") or 0.0
            ppos = _mpv(s, "playlist-pos-1")
            pcount = _mpv(s, "playlist-count")
    except Exception:
        return None
    if not path and not mtitle:
        return None
    low = {k.lower(): v for k, v in meta.items()} if isinstance(meta, dict) else {}
    artist = low.get("artist", "")
    title = low.get("title", "")
    if not title:
        title = mtitle or os.path.splitext(os.path.basename(path))[0]
    if not artist and " - " in title:
        artist, title = [x.strip() for x in title.split(" - ", 1)]
    return dict(status="Paused" if pause else "Playing", player="bgm mpv", artist=artist,
                title=title, album=low.get("album", ""), length=length, pos=pos, path=path,
                bgm=(ppos, pcount))


def read_player():
    return read_playerctl() or read_bgm()


# ---------- output ----------

SUBS_PORT = 47613  # the add-on POSTs captions here (127.0.0.1 only)
SUBS_FRESH = 7.0   # the add-on sends a heartbeat every 3 s while a video plays
_subs = {"data": None}
_wake = threading.Event()   # a caption arrived: print it now, not on the next tick


class _SubsHandler(BaseHTTPRequestHandler):
    # The custom header makes the browser send a CORS preflight (OPTIONS)
    # first. It is allowed only for add-on origins (moz-extension://), so web
    # pages cannot post captions here.
    def _ext_origin(self):
        o = self.headers.get("Origin", "")
        return o if o.startswith("moz-extension://") else ""

    def end_headers(self):
        o = self._ext_origin()
        if o:
            self.send_header("Access-Control-Allow-Origin", o)
        super().end_headers()

    def do_OPTIONS(self):
        o = self._ext_origin()
        self.send_response(204 if o else 403)
        if o:
            self.send_header("Access-Control-Allow-Methods", "POST")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Bar-Subs")
            self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        o = self.headers.get("Origin", "")
        if o and not self._ext_origin():
            self.send_response(403)
            self.end_headers()
            return
        if self.path != "/subs" or self.headers.get("X-Bar-Subs") != "1" or not 0 < n <= 8192:
            self.send_response(403)
            self.end_headers()
            return
        try:
            msg = json.loads(self.rfile.read(n))
            _subs["data"] = {
                "text": str(msg.get("text", ""))[:300],
                "playing": bool(msg.get("playing")),
                "title": str(msg.get("title", ""))[:200],
                "t": time.time(),
            }
            _wake.set()
            # last message received, for debugging: cat $XDG_RUNTIME_DIR/bar-subs-last.json
            try:
                with open(os.path.join(RUN, "bar-subs-last.json"), "w") as f:
                    json.dump(_subs["data"], f, ensure_ascii=False)
            except OSError:
                pass
            self.send_response(204)
        except (ValueError, AttributeError):
            self.send_response(400)
        self.end_headers()

    def log_message(self, *a):
        pass


def start_subs_server():
    """True once listening. False if the port is taken (e.g. an old copy still
    shutting down); the main loop retries."""
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", SUBS_PORT), _SubsHandler)
    except OSError:
        return False
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return True


def read_subs():
    """YouTube caption state from the "Bar subtitles" add-on, or None if stale."""
    d = _subs["data"]
    if not d or not d.get("playing") or time.time() - d.get("t", 0) > SUBS_FRESH:
        return None
    return d


def with_subs(p, subs):
    """A browser video with captions: name it by the page title and show the caption."""
    if subs is None or (p is not None and p["player"] != "firefox"):
        return p, None
    title = subs.get("title") or (p["title"] if p else "YouTube")
    text = subs.get("text", "").strip("♪♫ \t")   # captions wrap sung lines in notes
    return dict(status="Playing", player="browser (captions)", artist="", title=title,
                album="", length=0.0, pos=0.0, path=""), text


FLOW_MAX = 1500    # stream length cap; cutting it makes the chip fade once
FLOW_HOLD = 4.0    # keep a flowing stream on screen this long through a caption gap
_flow = {"stream": "", "last": "", "at": -1e9}


def _overlap(stream_words, new_words):
    """Words at the end of the stream that the new caption starts with."""
    for k in range(min(len(stream_words), len(new_words)), 0, -1):
        if stream_words[-k:] == new_words[:k]:
            return k
    return 0


def flow_caption(c, now):
    """Join captions that keep flowing (each one overlaps the last, like YouTube's
    automatic captions growing word by word and rolling up) into one stream.
    Returns (text, flowing). The bar scrolls a flowing stream to the left;
    a caption that does not continue the stream replaces it."""
    f = _flow
    if not c:
        if f["stream"] and now - f["at"] < FLOW_HOLD and f["stream"] != f["last"]:
            return f["stream"], True   # short gap inside a flow: keep showing it
        f["last"] = ""
        return "", False
    if c == f["last"]:
        return f["stream"], f["stream"] != c
    sw, cw = f["stream"].split(), c.split()
    k = _overlap(sw, cw)
    # one shared word is enough when the caption is just growing (old caption is
    # its prefix); otherwise ask for two, so a common word alone does not chain lines
    growing = f["last"] and c.startswith(f["last"])
    if f["stream"] and now - f["at"] < FLOW_HOLD and (growing or k >= 2 or (k >= 1 and len(cw) <= 2)):
        if k < len(cw):
            f["stream"] = (f["stream"] + " " + " ".join(cw[k:])).strip()
        if len(f["stream"]) > FLOW_MAX:
            cut = f["stream"].find(" ", len(f["stream"]) - FLOW_MAX // 3)
            f["stream"] = f["stream"][cut + 1:]
    else:
        f["stream"] = c
    f["last"], f["at"] = c, now
    return f["stream"], f["stream"] != c


def render(p, lines, pos, caption=None):
    if p is None:
        return {"text": "", "tooltip": "", "class": "hidden", "track": ""}
    track = p["title"]
    if p["artist"] and p["title"]:
        track = p["artist"] + " — " + p["title"]
    playing = p["status"] == "Playing"
    cls = ["playing"] if playing else ["paused"] if p["status"] == "Paused" else ["stopped"]
    icon = "🎵" if playing or p["status"] != "Paused" else "■"

    tip = track
    if p["player"] == "bgm mpv":
        if p["path"]:
            tip += "\nFile: " + p["path"]
        ppos, pcount = p.get("bgm", (None, None))
        if ppos and pcount:
            tip += "\nTrack %s of %s" % (ppos, pcount)
    elif p["album"]:
        tip += "\nAlbum: " + p["album"]
    tip += "\nPlayer: " + p["player"]

    text = icon + " " + clip(track, MAX_TRACK)
    if caption is not None:
        tip += "\nCaptions: YouTube"
        shown, flowing = flow_caption(caption, time.monotonic())
        if shown:
            text = icon + " " + shown   # not clipped: the bar scrolls what does not fit
            cls.append("lyric")
            if flowing:
                cls.append("flow")
    elif lines:
        tip += "\nLyrics: lrclib.net" if not p["path"] else "\nLyrics: found"
        if playing:
            cur = None
            for t, words in lines:
                if t <= pos + LEAD:
                    cur = words
                else:
                    break
            if cur:   # empty line = instrumental gap: show the track again
                text = icon + " " + clip(cur, MAX_LYRIC)
                cls.append("lyric")
    return {"text": text, "tooltip": tip, "class": cls, "track": track}


EFFECTS = "/home/iczo/syshelp/power-fx/effects.conf"
_fx = {"at": -1e9, "on": False}


def _on_ac():
    base = "/sys/class/power_supply"
    try:
        for ps in os.listdir(base):
            try:
                with open(os.path.join(base, ps, "type")) as f:
                    t = f.read().strip()
                with open(os.path.join(base, ps, "online")) as f:
                    if t in ("Mains", "USB", "USB_C") and f.read().strip() == "1":
                        return True
            except OSError:
                continue
    except OSError:
        pass
    return False


def fx_on(now):
    """Lyrics and captions are a power effect: on AC and "lyrics" on in effects.conf.
    Re-checked once a second."""
    if now - _fx["at"] >= 1.0:
        _fx["at"] = now
        try:
            with open(EFFECTS) as f:
                enabled = re.search(r"^\s*lyrics(\s|$)", f.read(), re.M) is not None
        except OSError:
            enabled = True   # like the bar: on if the file is unreadable
        _fx["on"] = enabled and _on_ac()
    return _fx["on"]


def main():
    test = None
    if len(sys.argv) >= 4 and sys.argv[1] == "--test":
        start = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
        test = dict(status="Playing", player="test", artist=sys.argv[2], title=sys.argv[3],
                    album="", length=0.0, pos=start, path="")
        t0 = time.monotonic() - start
    serving = True if test else start_subs_server()
    retry_at = time.monotonic() + 3
    parent = os.getppid()

    last_out = None
    p = None
    synced_at = -1e9
    base_pos = 0.0
    while True:
        now = time.monotonic()
        # the bar is gone (we were re-parented): quit, or we would hold the port
        if not test and os.getppid() != parent:
            return
        if not serving and now >= retry_at:
            serving, retry_at = start_subs_server(), now + 3
        if test:
            p = dict(test, pos=now - t0)
            base_pos, synced_at = p["pos"], now
        elif now - synced_at >= SYNC_EVERY:
            p = read_player()
            synced_at = now
            base_pos = p["pos"] if p else 0.0
        pos = base_pos + (now - synced_at if p and p["status"] == "Playing" else 0.0)
        fx = True if test else fx_on(now)
        shown, caption = (p, None) if test or not fx else with_subs(p, read_subs())
        lines = [] if not fx or caption is not None or not shown else \
            lyrics_for(shown["artist"], shown["title"], shown["album"], shown["length"], shown["path"])
        out = json.dumps(render(shown, lines, pos, caption), ensure_ascii=False)
        if out != last_out:
            if test:
                print("%7.1f  " % pos, end="")
            print(out, flush=True)
            last_out = out
        _wake.wait(TICK if fx else 1.0)
        _wake.clear()


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
