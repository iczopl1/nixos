#!/usr/bin/env python3
"""
T3.9: Scraper planu zajęć PRz dla grup A3S i A3S-L3.
Wyjście: tygodniowy plan w terminalu + opcjonalnie plik .ics.
Użycie: prz-schedule.py [--ics <plik.ics>] [--week a|b|today]
"""
import sys, re, argparse, urllib.request, html.parser
from datetime import date, datetime, timedelta

URL = "https://pei.prz.edu.pl/as/Zima2026_groups_days_horizontal.html"
GROUPS = {"A3S", "A3S-L3"}  # grupy do pokazania

# Semestr zimowy 2026/27: poniedziałek 06.10.2026 = tydzień A (1.)
SEMESTER_START = date(2026, 10, 6)   # poniedziałek
SEMESTER_END   = date(2027, 2, 14)
WEEK_A_START   = SEMESTER_START      # tydzień A = tygodnie nieparzyste (1, 3, 5, …)

DAYS_PL = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek"]
DAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
COL_TO_DAY   = {i: i // 2 for i in range(10)}   # col 0,1→0  2,3→1  …
COL_TO_WEEK  = {i: "AB"[i % 2] for i in range(10)}  # 0,2,4,6,8→A  1,3,5,7,9→B


# ---------------------------------------------------------------------------
# Parsowanie HTML
# ---------------------------------------------------------------------------
class TableParser(html.parser.HTMLParser):
    """Zbiera zawartość tabeli id=table_31 (A3S)."""
    def __init__(self):
        super().__init__()
        self.in_target   = False
        self.depth       = 0
        self.target_id   = "table_31"
        self.chunks      = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == "table" and d.get("id") == self.target_id:
            self.in_target = True
            self.depth = 1
            self.chunks.append(f"<{tag}")
            for k, v in attrs:
                self.chunks.append(f' {k}="{v}"')
            self.chunks.append(">")
            return
        if self.in_target:
            self.depth += (tag == "table")
            self.chunks.append(f"<{tag}")
            for k, v in attrs:
                self.chunks.append(f' {k}="{v or ""}"')
            self.chunks.append(">")

    def handle_endtag(self, tag):
        if not self.in_target:
            return
        self.chunks.append(f"</{tag}>")
        if tag == "table":
            self.depth -= 1
            if self.depth == 0:
                self.in_target = False

    def handle_data(self, data):
        if self.in_target:
            self.chunks.append(html.parser.unescape(data) if hasattr(html.parser, 'unescape') else data)

    def handle_entityref(self, name):
        if self.in_target:
            self.chunks.append({"amp": "&", "lt": "<", "gt": ">", "quot": '"', "nbsp": " "}.get(name, ""))

    def handle_charref(self, name):
        if self.in_target:
            try:
                n = int(name[1:], 16) if name.startswith("x") else int(name)
                self.chunks.append(chr(n))
            except Exception:
                pass

    def result(self):
        return "".join(self.chunks)


def strip_tags(s):
    return re.sub(r"<[^>]+>", "", s).strip()


def parse_event(cell_html):
    """Wyciąga (group, subject, atype, teacher, room) z HTML komórki."""
    if 'class="detailed"' not in cell_html:
        return None
    grp     = strip_tags(re.search(r'studentsset[^>]*>(.*?)</td>', cell_html, re.S).group(1) if re.search(r'studentsset[^>]*>(.*?)</td>', cell_html, re.S) else "")
    subj_m  = re.search(r'class="subject">(.*?)</span>', cell_html, re.S)
    atype_m = re.search(r'class="activitytag">(.*?)</span>', cell_html, re.S)
    teach_m = re.search(r'class="teacher[^"]*"[^>]*>[^<]*<td[^>]*>(.*?)</td>', cell_html, re.S)
    room_m  = re.search(r'class="room[^"]*"[^>]*>[^<]*<td[^>]*>(.*?)</td>', cell_html, re.S)
    return {
        "group":   strip_tags(grp),
        "subject": strip_tags(subj_m.group(1) if subj_m else ""),
        "atype":   strip_tags(atype_m.group(1) if atype_m else "").strip(", "),
        "teacher": strip_tags(teach_m.group(1) if teach_m else ""),
        "room":    strip_tags(room_m.group(1)  if room_m  else ""),
    }


def parse_time(raw):
    """'➜8:45-9:00' → '08:45', '09:00'"""
    m = re.search(r'(\d+:\d+)-(\d+:\d+)', raw)
    if not m:
        return None, None
    def norm(t):
        h, mi = t.split(":")
        return f"{int(h):02d}:{mi}"
    return norm(m.group(1)), norm(m.group(2))


def fetch_html():
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read().decode("utf-8")


def parse_schedule(html_text):
    """Zwraca listę eventów: {day, week, time_start, time_end, group, subject, atype, teacher, room}"""
    p = TableParser()
    p.feed(html_text)
    tbl = p.result()
    if not tbl:
        print("BŁĄD: nie znaleziono tabeli A3S (table_31)", file=sys.stderr)
        sys.exit(1)

    rows = re.findall(r'<tr>(.*?)</tr>', tbl, re.S)
    # Kolumny z thead
    thead_rows = re.findall(r'<tr>(.*?)</tr>', re.search(r'<thead>(.*?)</thead>', tbl, re.S).group(1), re.S)
    # Pomijamy thead, bierzemy tbody
    tbody_m = re.search(r'<tbody>(.*?)</tbody>', tbl, re.S)
    if not tbody_m:
        print("BŁĄD: brak tbody", file=sys.stderr)
        sys.exit(1)

    tbody_rows = re.findall(r'<tr>(.*?)</tr>', tbody_m.group(1), re.S)

    # Zbieramy surowe sloty: [col][list of (time_start, time_end, event)]
    raw_by_col = {i: [] for i in range(10)}

    for row in tbody_rows:
        # Czas z th.yAxis
        yaxis_m = re.search(r'class="yAxis">(.*?)</th>', row, re.S)
        if not yaxis_m:
            continue
        t_start, t_end = parse_time(strip_tags(yaxis_m.group(1)))
        if not t_start:
            continue

        # Komórki td (bez th)
        cells = re.findall(r'<td(?:[^>]*)>(.*?)</td>', row, re.S)
        for col_idx, cell_html in enumerate(cells[:10]):
            evt = parse_event(cell_html)
            if evt and any(g in evt["group"] for g in GROUPS):
                raw_by_col[col_idx].append((t_start, t_end, evt))

    # Merge consecutive slots tego samego eventu (te same pola)
    def event_key(e):
        return (e["group"], e["subject"], e["teacher"], e["room"])

    events = []
    for col_idx in range(10):
        slots = raw_by_col[col_idx]
        if not slots:
            continue
        day  = COL_TO_DAY[col_idx]
        week = COL_TO_WEEK[col_idx]
        merged_start, merged_end, cur_evt = slots[0]
        for t_s, t_e, evt in slots[1:]:
            if event_key(evt) == event_key(cur_evt) and t_s == merged_end:
                merged_end = t_e
            else:
                events.append({"day": day, "week": week,
                                "time_start": merged_start, "time_end": merged_end,
                                **cur_evt})
                merged_start, merged_end, cur_evt = t_s, t_e, evt
        events.append({"day": day, "week": week,
                        "time_start": merged_start, "time_end": merged_end,
                        **cur_evt})

    return sorted(events, key=lambda e: (e["day"], e["week"], e["time_start"]))


# ---------------------------------------------------------------------------
# Wyświetlanie
# ---------------------------------------------------------------------------
def which_week(d: date) -> str:
    """Zwraca 'A' lub 'B' dla danej daty."""
    delta = (d - WEEK_A_START).days
    if delta < 0:
        return "?"
    week_no = delta // 7
    return "A" if week_no % 2 == 0 else "B"


def show_schedule(events, week_filter=None):
    today = date.today()
    cur_week = which_week(today)
    if week_filter == "today":
        week_filter = cur_week
        day_filter = today.weekday()   # 0=pon
    else:
        day_filter = None

    print(f"Plan PRz – grupy: {', '.join(sorted(GROUPS))}")
    if week_filter:
        print(f"Tydzień: {week_filter}  (dziś: {today.strftime('%Y-%m-%d')}, tydzień {cur_week})")
    print("─" * 72)

    prev_day = None
    for e in events:
        if week_filter and e["week"] != week_filter:
            continue
        if day_filter is not None and e["day"] != day_filter:
            continue
        if e["day"] != prev_day:
            print(f"\n  {DAYS_PL[e['day']]} (tydzień {e['week']})")
            prev_day = e["day"]
        subj_short = re.sub(r'\s*\(.*?\)\s*', '', e["subject"])[:38]
        print(f"    {e['time_start']}–{e['time_end']}  {subj_short:<38}  {e['room']:<6}  {e['group']}")
    print()


# ---------------------------------------------------------------------------
# Generowanie .ics
# ---------------------------------------------------------------------------
def make_ics(events) -> str:
    # Mapowanie dnia tygodnia (0=pon) na datę pierwszego wystąpienia w semestrze
    # Tydzień A: SEMESTER_START (poniedziałek 06.10.2026)
    # Tydzień B: SEMESTER_START + 7
    week_offsets = {"A": 0, "B": 7}
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//PRz-Scraper//PL",
        "X-WR-CALNAME:Plan PRz A3S",
        "X-WR-TIMEZONE:Europe/Warsaw",
        "CALSCALE:GREGORIAN",
    ]

    def fmt_dt(d: date, t: str) -> str:
        h, mi = t.split(":")
        return f"{d.strftime('%Y%m%d')}T{h}{mi}00"

    until = SEMESTER_END.strftime("%Y%m%d") + "T235959Z"

    for e in events:
        first_mon = SEMESTER_START + timedelta(days=week_offsets[e["week"]])
        event_date = first_mon + timedelta(days=e["day"])
        uid = f"prz-{e['day']}-{e['week']}-{e['time_start'].replace(':','')}@prz"
        summary = re.sub(r'\s*\(.*?\)\s*', '', e["subject"]).strip()
        desc = f"{e['atype']} | {e['teacher']}"
        lines += [
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTART:{fmt_dt(event_date, e['time_start'])}",
            f"DTEND:{fmt_dt(event_date, e['time_end'])}",
            f"RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL={until}",
            f"SUMMARY:{summary}",
            f"DESCRIPTION:{desc}",
            f"LOCATION:{e['room']}",
            "END:VEVENT",
        ]

    lines.append("END:VCALENDAR")
    return "\r\n".join(lines)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Plan zajęć PRz A3S/A3S-L3")
    ap.add_argument("--ics",  metavar="PLIK", help="zapisz do pliku .ics")
    ap.add_argument("--week", choices=["a", "b", "A", "B", "today"], default=None,
                    help="filtruj tydzień A/B lub pokaż tylko dziś")
    ap.add_argument("--all", action="store_true", help="pokaż oba tygodnie")
    args = ap.parse_args()

    week_arg = None if args.all else (args.week.upper() if args.week else which_week(date.today()))

    try:
        html_text = fetch_html()
    except Exception as ex:
        print(f"Błąd pobierania: {ex}", file=sys.stderr)
        sys.exit(1)

    events = parse_schedule(html_text)

    show_schedule(events, week_filter=None if args.all else week_arg)

    if args.ics:
        ics = make_ics(events)
        with open(args.ics, "w", encoding="utf-8") as f:
            f.write(ics)
        print(f"Zapisano: {args.ics}  ({len(events)} eventów)")


if __name__ == "__main__":
    main()
