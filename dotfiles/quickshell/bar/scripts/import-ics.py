#!/usr/bin/env python3
"""Import .ics files into the quickshell calendar store.

Usage: import-ics.py [--mirror] FILE.ics [FILE2.ics ...]
--mirror: events tagged src="sync"; events from an earlier mirror run that the file
no longer has are removed (phone deletions propagate).
Store:  ~/.local/share/quickshell-calendar/events.json
Events with the same UID and start replace the stored copy, so re-importing is safe.
Times: UTC as ISO "...Z"; floating times without Z (local); all-day as YYYY-MM-DD
(end exclusive). EXDATE becomes local YYYY-MM-DD keys.
"""
import json, os, re, sys
from datetime import datetime, timezone

STORE = os.path.expanduser("~/.local/share/quickshell-calendar/events.json")


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def unescape(v):
    return (v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
             .replace("\\;", ";").replace("\\\\", "\\"))


def split_line(line):
    head, _, val = line.partition(":")
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v
    return parts[0].upper(), params, val


def conv(val, params=None):
    """-> (iso string, all_day)"""
    v = val.strip()
    if re.fullmatch(r"\d{8}", v):
        return f"{v[0:4]}-{v[4:6]}-{v[6:8]}", True
    m = re.fullmatch(r"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)", v)
    if not m:
        return None, False
    y, mo, d, h, mi, s, z = m.groups()
    return f"{y}-{mo}-{d}T{h}:{mi}:{s}{'Z' if z else ''}", False


def local_key(iso):
    if len(iso) == 10:
        return iso
    if iso.endswith("Z"):
        dt = datetime.fromisoformat(iso[:-1]).replace(tzinfo=timezone.utc).astimezone()
        return dt.strftime("%Y-%m-%d")
    return iso[:10]


def parse_rrule(val):
    kv = dict(p.split("=", 1) for p in val.split(";") if "=" in p)
    r = {"freq": kv.get("FREQ", "").upper(), "interval": int(kv.get("INTERVAL", "1"))}
    if "COUNT" in kv:
        r["count"] = int(kv["COUNT"])
    if "UNTIL" in kv:
        iso, _ = conv(kv["UNTIL"])
        if iso:
            r["until"] = iso
    if "BYDAY" in kv:
        r["byday"] = [d[-2:] for d in kv["BYDAY"].split(",")]
    return r if r["freq"] in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY") else None


def parse(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = unfold(f.read())
    out, cur, depth, closer = [], None, 0, ""
    for line in lines:
        if cur is None and line in ("BEGIN:VEVENT", "BEGIN:VTODO"):
            # tasks (VTODO) become events marked task=true
            cur, depth = {"exdate": []}, 0
            closer = "END:" + line[6:]
            if line == "BEGIN:VTODO":
                cur["task"] = True
        elif cur is not None and line.startswith("BEGIN:"):
            depth += 1
        elif cur is not None and line.startswith("END:") and line != closer:
            depth -= 1
        elif line == closer and cur is not None:
            if not cur.get("start") and cur.get("due"):   # task with only a due date
                cur["start"] = cur["due"]
                cur["allDay"] = len(cur["due"]) == 10
            cur.pop("due", None)
            if cur.get("task"):
                cur["end"] = cur.get("end") or cur["start"]   # a task is a point in time
                cur["done"] = bool(cur.get("done"))
            elif "done" in cur:
                del cur["done"]                              # STATUS:CONFIRMED etc. on events
            if cur.get("start"):
                cur.setdefault("title", "(no title)")
                cur.setdefault("uid", "ics-" + str(abs(hash(cur["start"] + cur["title"]))))
                out.append(cur)
            cur = None
        elif cur is not None and depth == 0:
            name, params, val = split_line(line)
            if name == "SUMMARY":
                cur["title"] = unescape(val)
            elif name == "UID":
                cur["uid"] = val.strip()
            elif name == "LOCATION":
                cur["location"] = unescape(val)
            elif name == "DESCRIPTION":
                cur["desc"] = unescape(val)
            elif name == "DTSTART":
                cur["start"], cur["allDay"] = conv(val)
            elif name == "DUE":
                cur["due"], _ = conv(val)
            elif name == "STATUS":
                cur["done"] = val.strip().upper() == "COMPLETED"
            elif name == "CATEGORIES":
                cur["cat"] = unescape(val)
            elif name == "DTEND":
                cur["end"], _ = conv(val)
            elif name == "RRULE":
                r = parse_rrule(val)
                if r:
                    cur["rrule"] = r
            elif name == "EXDATE":
                for part in val.split(","):
                    iso, _ = conv(part)
                    if iso:
                        cur["exdate"].append(local_key(iso))
    return out


def main(paths, mirror=False):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    store = {}
    if os.path.exists(STORE):
        with open(STORE, encoding="utf-8") as f:
            store = {e["uid"] + "|" + e["start"]: e for e in json.load(f)}
    n = 0
    fresh = {}
    for p in paths:
        for e in parse(os.path.expanduser(p)):
            if mirror:
                e["src"] = "sync"
            fresh[e["uid"] + "|" + e["start"]] = e
            n += 1
    if mirror:
        # the file is the truth for everything it synced before: drop what it no longer has
        store = {k: v for k, v in store.items() if v.get("src") != "sync"}
    store.update(fresh)
    tmp = STORE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(list(store.values()), f, ensure_ascii=False, indent=1)
    os.replace(tmp, STORE)
    print(f"imported {n} events, {len(store)} in store")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    args = sys.argv[1:]
    mirror = "--mirror" in args
    main([a for a in args if a != "--mirror"], mirror)
