#!/usr/bin/env python3
"""Export the quickshell calendar store to an .ics file.

Usage: export-ics.py [OUT.ics]     (default: ~/Downloads/calendar-YYYYMMDD-HHMMSS.ics)
Events become VEVENT, tasks VTODO. Prints the path it wrote.
"""
import json, os, re, sys
from datetime import datetime, timezone

STORE = os.path.expanduser("~/.local/share/quickshell-calendar/events.json")


def esc(v):
    return (v.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
             .replace("\r\n", "\\n").replace("\n", "\\n"))


def fold(line):
    # 75 octets per line, continuation lines start with one space
    out, cur, size = [], "", 0
    for ch in line:
        n = len(ch.encode("utf-8"))
        if size + n > (75 if not out else 74):
            out.append(cur)
            cur, size = "", 0
        cur += ch
        size += n
    out.append(cur)
    return "\r\n ".join(out)


def dt_prop(name, iso, all_day):
    """-> (line) for an ISO string from the store."""
    if all_day or len(iso) == 10:
        return f"{name};VALUE=DATE:{iso[:10].replace('-', '')}"
    return f"{name}:{iso.replace('-', '').replace(':', '')}"


def exdate_line(ev, key):
    if ev.get("allDay"):
        return "EXDATE;VALUE=DATE:" + key.replace("-", "")
    s = ev["start"]
    if s.endswith("Z"):
        local = datetime.fromisoformat(s[:-1]).replace(tzinfo=timezone.utc).astimezone()
    else:
        local = datetime.fromisoformat(s)
    y, m, d = (int(x) for x in key.split("-"))
    occ = local.replace(year=y, month=m, day=d)
    if occ.tzinfo is None:
        return "EXDATE:" + occ.strftime("%Y%m%dT%H%M%S")
    return "EXDATE:" + occ.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def rrule_line(r):
    parts = [f"FREQ={r['freq']}"]
    if r.get("interval", 1) != 1:
        parts.append(f"INTERVAL={r['interval']}")
    if r.get("count"):
        parts.append(f"COUNT={r['count']}")
    if r.get("until"):
        parts.append("UNTIL=" + r["until"].replace("-", "").replace(":", ""))
    if r.get("byday"):
        parts.append("BYDAY=" + ",".join(r["byday"]))
    return "RRULE:" + ";".join(parts)


def main(out):
    with open(STORE, encoding="utf-8") as f:
        events = json.load(f)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell-calendar//EN", "CALSCALE:GREGORIAN"]
    for ev in events:
        task = bool(ev.get("task"))
        kind = "VTODO" if task else "VEVENT"
        lines += [f"BEGIN:{kind}", "UID:" + ev["uid"], "DTSTAMP:" + stamp,
                  "SUMMARY:" + esc(ev.get("title", ""))]
        lines.append(dt_prop("DTSTART", ev["start"], ev.get("allDay")))
        if ev.get("end") and not task:
            lines.append(dt_prop("DTEND", ev["end"], ev.get("allDay")))
        if ev.get("location"):
            lines.append("LOCATION:" + esc(ev["location"]))
        if ev.get("desc"):
            lines.append("DESCRIPTION:" + esc(ev["desc"]))
        if ev.get("cat"):
            lines.append("CATEGORIES:" + esc(ev["cat"]))
        if task:
            lines.append("STATUS:" + ("COMPLETED" if ev.get("done") else "NEEDS-ACTION"))
        if ev.get("rrule"):
            lines.append(rrule_line(ev["rrule"]))
            for k in ev.get("exdate") or []:
                lines.append(exdate_line(ev, k))
        lines.append(f"END:{kind}")
    lines.append("END:VCALENDAR")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write("\r\n".join(fold(l) for l in lines) + "\r\n")
    print(out)


if __name__ == "__main__":
    default = os.path.expanduser("~/Downloads/calendar-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".ics")
    main(os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else default)
