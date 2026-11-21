#!/usr/bin/env python3
"""Print clickable accessibility elements as wl-kbptr stdin rects.

Output: one "WxH+X+Y" per line, output-local (what wl-kbptr source=stdin wants).
Exit 0 + lines  -> use them. Windows without fields get picture-based boxes inside
that window only. Exit 3 -> nothing usable; the caller reports it, it never falls back to whole-screen vision.
--bar (or HINT_BAR=1) prints only the bar (waybar) fields.
Covers every visible Hyprland window that exposes AT-SPI, plus layer surfaces
(waybar). Windows without AT-SPI (terminals) are skipped; see FOCUS_ONLY.
Never clicks anything: it only reads the accessibility tree.
"""
import json, subprocess, sys, time, os, configparser, threading
from concurrent.futures import ThreadPoolExecutor

import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, Gio, GLib

MAX_NODES = 6000  # per window
MAX_CHILDREN = 500  # per node: a 100k-link list must not stall the keybind
NO_VISION = os.environ.get("HINT_NO_VISION") == "1"  # windows with no fields get no boxes at all
MAX_PER_SOURCE = 300  # per window/bar, so a busy page cannot push the bar out
MAX_RECTS = 400  # total boxes; more than that is unreadable and slow to label
ROLES = {
    Atspi.Role.PUSH_BUTTON, Atspi.Role.TOGGLE_BUTTON, Atspi.Role.LINK,
    Atspi.Role.CHECK_BOX, Atspi.Role.RADIO_BUTTON, Atspi.Role.MENU_ITEM,
    Atspi.Role.CHECK_MENU_ITEM, Atspi.Role.RADIO_MENU_ITEM, Atspi.Role.MENU,
    Atspi.Role.PAGE_TAB, Atspi.Role.COMBO_BOX, Atspi.Role.ENTRY,
    Atspi.Role.PASSWORD_TEXT, Atspi.Role.SPIN_BUTTON, Atspi.Role.SLIDER,
    Atspi.Role.TREE_ITEM,
    Atspi.Role.BUTTON_MENU if hasattr(Atspi.Role, "BUTTON_MENU") else Atspi.Role.PUSH_BUTTON,
}
TEXT_ROLES = {Atspi.Role.ENTRY, Atspi.Role.PASSWORD_TEXT, Atspi.Role.SPIN_BUTTON}
PRUNE_HIDDEN = {Atspi.Role.DOCUMENT_WEB, Atspi.Role.DOCUMENT_FRAME, Atspi.Role.MENU,
                Atspi.Role.POPUP_MENU, Atspi.Role.PAGE_TAB_LIST}
MIN_W, MIN_H = 6, 6


def hypr(*a):
    return json.loads(subprocess.check_output(["hyprctl", "-j", *a], text=True))


def _hypr_ipc(name):
    """Ask Hyprland directly over its socket: ~1 ms instead of a hyprctl process."""
    import socket
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket.sock")
    with socket.socket(socket.AF_UNIX) as c:
        c.settimeout(1.0)
        c.connect(path)
        c.sendall(b"j/" + name.encode())
        chunks, size, end = [], 0, time.monotonic() + 1.0
        while True:
            d = c.recv(1 << 16)
            if not d:
                break
            chunks.append(d)
            size += len(d)
            if size > 4 << 20 or time.monotonic() > end:
                raise RuntimeError("hyprland socket reply too big or slow")
    return json.loads(b"".join(chunks))


def hypr_many(*names):
    """Several Hyprland queries; falls back to hyprctl if the socket is unavailable."""
    try:
        return [_hypr_ipc(n) for n in names]
    except Exception:
        pass
    procs = [subprocess.Popen(["hyprctl", "-j", n], stdout=subprocess.PIPE, text=True) for n in names]
    out = []
    try:
        for n, pr in zip(names, procs):
            txt = pr.communicate()[0]
            if pr.returncode:
                raise RuntimeError(f"hyprctl {n} failed")
            out.append(json.loads(txt))
    finally:
        for pr in procs:  # on failure, reap the rest instead of leaving zombies and pipes
            if pr.poll() is None:
                pr.kill()
            pr.communicate()
    return out


def _mmsg(*a):
    return json.loads(subprocess.check_output(["mmsg", "get", *a], text=True, timeout=1))


def mango_border():
    """borderpx from the mango config (last one wins, like mango); 2 = what this setup draws without one."""
    bw = 2
    d = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "mango")
    for name in ("config.conf", "mango-wal.conf"):
        try:
            with open(os.path.join(d, name)) as f:
                for line in f:
                    k, _, v = line.partition("=")
                    if k.strip() == "borderpx" and v.strip().isdigit():
                        bw = int(v)
        except OSError:
            pass
    return bw


def mango_many():
    """Mango's answers in Hyprland's shape, so main() keeps one code path.
    Mango has no workspaces (tags: is_visible covers it), no focus history and no
    layer pid/size, so bars get no fields there. Its monitor sizes are logical."""
    mons = _mmsg("all-monitors")["monitors"]
    try:
        act = _mmsg("focusing-client")
    except Exception:
        act = {}
    if not isinstance(act, dict) or act.get("id") is None:
        act = {}
    focus = act.get("monitor") or _mmsg("cursorpos").get("monitor")
    bw = mango_border()

    def client(c):
        # Mango's geometry includes the border; the border in a screenshot frames the
        # whole window, so picture detection would find one giant box.
        b = 0 if c["is_fullscreen"] else bw
        return {"address": c["id"], "pid": c["pid"], "title": c["title"], "class": c["appid"],
                "at": [c["x"] + b, c["y"] + b], "size": [c["width"] - 2 * b, c["height"] - 2 * b],
                "floating": c["is_floating"], "fullscreen": c["is_fullscreen"],
                "mapped": True, "hidden": not c["is_visible"] or c["is_minimized"],
                "workspace": {"id": 0}, "monitor": c["monitor"],
                "focusHistoryID": 0 if c["is_focused"] else -1}

    monitors = [dict(m, id=m["name"], focused=m["name"] == focus, activeWorkspace={"id": 0}, logical=True)
                for m in mons]
    return monitors, [client(c) for c in _mmsg("all-clients")["clients"]], client(act) if act else {}, \
        _mmsg("all-layers")["layers"]


def mango_layers(names, by_pid, mon_w):
    """Mango gives a layer surface's name (its namespace) but no pid, place or size.
    The name's first word must be the accessible app's name ("quickshell-bar" ->
    quickshell); the size comes from that app's bar-shaped windows. Assumes a bar on
    the top edge with equal left/right margins (Bar.qml: top 1, sides 14)."""
    words = {n.split("-")[0].lower() for n in names}
    out = []
    for pid, apps in by_pid.items():
        for app in apps:
            try:
                if (app.get_name() or "").lower() not in words:
                    continue
                for j in range(app.get_child_count()):
                    e = app.get_child_at_index(j).get_extents(Atspi.CoordType.WINDOW)
                    if 0 < e.height < 100 and e.width > 4 * e.height:
                        out.append({"pid": pid, "w": e.width, "h": e.height,
                                    "x": round((mon_w - e.width) / 2), "y": 0})
            except Exception:
                continue
    return out


def has_action(n):
    try:
        ai = n.get_action_iface()
        return ai is not None and ai.get_n_actions() > 0
    except Exception:
        return False


MAX_GENERIC = (320, 64)  # click-action divs bigger than this are layout, not controls
ACTION_ROLES = {Atspi.Role.PANEL, Atspi.Role.SECTION, Atspi.Role.IMAGE, Atspi.Role.ICON,
                Atspi.Role.LABEL, Atspi.Role.LIST_ITEM, Atspi.Role.TABLE_CELL}
if hasattr(Atspi.Role, "GENERIC"):
    ACTION_ROLES.add(Atspi.Role.GENERIC)


def clickable(n, role):
    """-> 0 not clickable, 1 clickable, 2 clickable only if small."""
    if role in ROLES and role not in ACTION_ROLES:
        return 1
    if role in ACTION_ROLES and has_action(n):
        return 2
    return 0


def walk(win, ox, oy, clip, layer=False):
    """DFS with a node cap (no time limit) -> (list of (x, y, w, h) in global coordinates,
    number of clickable nodes the tree exposed; 0 means it exposes no fields at all).

    layer=True (waybar and other bars): module labels and tray icons count as
    clickable too, because bars rarely expose click actions through AT-SPI.
    """
    out = []
    stack = [win]
    nodes = 0
    exposed = 0
    while stack:
        if nodes > MAX_NODES:
            break
        n = stack.pop()
        nodes += 1
        try:
            st = n.get_state_set()
            role = n.get_role()
            showing = st.contains(Atspi.StateType.SHOWING)
            # Only prune subtrees that are big and known-hidden (background tabs,
            # closed menus); plain wrappers may be "not showing" yet hold live content.
            if not showing and role in PRUNE_HIDDEN:
                continue
            # GTK4 sets SENSITIVE but never ENABLED; most toolkits set both
            usable = st.contains(Atspi.StateType.ENABLED) or st.contains(Atspi.StateType.SENSITIVE)
            kind = clickable(n, role) if showing and usable else 0
            if layer and not kind and showing and role in (Atspi.Role.LABEL, Atspi.Role.ICON):
                kind = 1
            if kind:
                exposed += 1
                e = n.get_extents(Atspi.CoordType.WINDOW)
                if not (kind == 2 and (e.width > MAX_GENERIC[0] or e.height > MAX_GENERIC[1])):
                    x, y = e.x + ox, e.y + oy
                    cx, cy, cw, ch = clip
                    x2, y2 = min(x + e.width, cx + cw), min(y + e.height, cy + ch)
                    x, y = max(x, cx), max(y, cy)
                    if x2 - x >= MIN_W and y2 - y >= MIN_H:
                        out.append((x, y, x2 - x, y2 - y))
            for i in range(min(n.get_child_count(), MAX_CHILDREN) - 1, -1, -1):
                c = n.get_child_at_index(i)
                if c is not None:
                    stack.append(c)
        except Exception:
            continue
    return out, exposed


HOLE_ROLES = {Atspi.Role.LIST, Atspi.Role.TOOL_BAR, Atspi.Role.TREE, Atspi.Role.MENU_BAR, Atspi.Role.PAGE_TAB_LIST}

# Firefox reports the items of a closed menu as showing while the menu itself is not.
HIDE_CHECK = {Atspi.Role.MENU_ITEM, Atspi.Role.CHECK_MENU_ITEM, Atspi.Role.RADIO_MENU_ITEM,
              Atspi.Role.MENU, Atspi.Role.PAGE_TAB}


def hidden_by_ancestor(n, memo):
    """True if a closed menu / hidden tab list / hidden document sits just above n.
    memo caches the answer per parent: a menu's items share one parent."""
    p = n.get_parent()
    for _ in range(3):  # item -> menu -> submenu header -> menu
        if p is None:
            return False
        if p in memo:
            return memo[p]
        hidden = p.get_role() in PRUNE_HIDDEN and not p.get_state_set().contains(Atspi.StateType.SHOWING)
        memo[p] = hidden
        if hidden:
            return True
        p = p.get_parent()
    return False


_a11y_conn = None
_a11y_lock = threading.Lock()


def a11y_connection():
    """Our own connection to the accessibility bus, for sending many requests at once."""
    global _a11y_conn
    with _a11y_lock:
        if _a11y_conn is None or _a11y_conn.is_closed():
            sess = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            addr = sess.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", None,
                                  GLib.VariantType("(s)"), Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
            _a11y_conn = Gio.DBusConnection.new_for_address_sync(
                addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
                None, None)
        return _a11y_conn


def bulk_extents(nodes, timeout=2.0):
    """Window-relative (x, y, w, h) of every node, asking the app for all of them
    at once instead of waiting for each answer. None where an answer is missing;
    the caller then asks that node the slow way."""
    out = [None] * len(nodes)
    if not nodes:
        return out
    try:
        conn = a11y_connection()
        ctx = GLib.MainContext.new()
        ctx.push_thread_default()  # replies are delivered to this thread, not another walk's
        try:
            loop = GLib.MainLoop.new(ctx, False)
            cancel = Gio.Cancellable()
            pending = [len(nodes)]

            def make(i):
                def done(_src, res):
                    try:
                        out[i] = tuple(conn.call_finish(res).unpack()[0])
                    except Exception:
                        pass
                    pending[0] -= 1
                    if pending[0] == 0:
                        loop.quit()
                return done

            for i, n in enumerate(nodes):
                try:
                    conn.call(n.app.bus_name, n.path, "org.a11y.atspi.Component", "GetExtents",
                              GLib.Variant("(u)", (int(Atspi.CoordType.WINDOW),)), GLib.VariantType("((iiii))"),
                              Gio.DBusCallFlags.NONE, 1000, cancel, make(i))
                except Exception:
                    pending[0] -= 1
            if pending[0] > 0:
                stop = GLib.timeout_source_new(int(timeout * 1000))
                stop.set_callback(lambda *_: (loop.quit(), False)[1])
                stop.attach(ctx)
                loop.run()
                stop.destroy()
            if pending[0] > 0:  # late replies would wait forever in this context, holding memory
                cancel.cancel()
                while pending[0] > 0 and ctx.iteration(True):
                    pass
        finally:
            ctx.pop_thread_default()
    except Exception as ex:
        print(f"hint-atspi: pipelined reads failed: {ex}", file=sys.stderr)
    if any(e is None for e in out):
        print(f"hint-atspi: {sum(e is None for e in out)} of {len(out)} positions asked one by one", file=sys.stderr)
    return out


def merge_rows(cells):
    """Table cells that sit side by side in one row (icon, name, size, date...) all
    do the same thing when clicked, so a row gets one box instead of one per cell."""
    lines = []  # cells whose top and height agree, in order of appearance
    for c in sorted(cells, key=lambda c: (c[1], c[3])):
        if lines and abs(lines[-1][0][1] - c[1]) <= 2 and abs(lines[-1][0][3] - c[3]) <= 2:
            lines[-1].append(c)
        else:
            lines.append([c])
    rows, tall = [], 0
    for line in lines:
        cur = None
        for x, y, w, h in sorted(line):
            if cur and x <= cur[0] + cur[2] + 8:
                cur[2] = max(cur[0] + cur[2], x + w) - cur[0]
            else:
                cur = [x, y, w, h]
                rows.append(cur)
    for r in rows[:]:
        if r[3] > MAX_GENERIC[1]:
            rows.remove(r)
            tall += 1
    if tall:
        print(f"hint-atspi: {tall} table rows taller than {MAX_GENERIC[1]}px left out", file=sys.stderr)
    return [tuple(r) for r in rows]


def walk_fast(win, ox, oy, clip, layer=False):
    """Same boxes as walk(), but the app does the searching: one Collection
    query per rule instead of ~7 D-Bus calls per node. Returns (boxes, number of
    candidates the app exposed). None = the app has no Collection (GTK, Qt...),
    so the caller walks the tree instead."""
    try:
        col = win.get_collection_iface()
        if col is None:
            return None
        states = Atspi.StateSet.new([Atspi.StateType.SHOWING, Atspi.StateType.SENSITIVE])
        direct = set(ROLES) - ACTION_ROLES
        if layer:
            direct |= {Atspi.Role.LABEL, Atspi.Role.ICON}

        def rule(roles, ifaces=None):
            return Atspi.MatchRule.new(states, Atspi.CollectionMatchType.ALL, None, Atspi.CollectionMatchType.ALL,
                                       list(roles), Atspi.CollectionMatchType.ANY, ifaces,
                                       Atspi.CollectionMatchType.ANY if ifaces else Atspi.CollectionMatchType.ALL, False)

        # (rule, kind, check hidden menus/tabs, max matches). Every match costs a D-Bus
        # call for its extents, so the plain roles skip the hidden-menu check and the
        # generic click-action nodes (the long tail) are capped.
        rules = [(rule(direct - HIDE_CHECK), 1, False, MAX_PER_SOURCE + 100),
                 (rule(direct & HIDE_CHECK), 1, True, 100),
                 (rule(ACTION_ROLES - direct - {Atspi.Role.TABLE_CELL}, ["action"]), 2, False, MAX_PER_SOURCE + 100),
                 (rule({Atspi.Role.TABLE_CELL}, ["action"]), 3, False, MAX_PER_SOURCE + 100)]
        cx, cy, cw, ch = clip
        memo = {}
        cands = []  # (node, kind)
        for r, kind, check, cap in rules:
            found = col.get_matches(r, Atspi.CollectionSortOrder.CANONICAL, cap, True)
            if len(found) >= cap:
                print(f"hint-atspi: more than {cap} matches for one rule, the rest get no hint", file=sys.stderr)
            for n in found:
                if check and hidden_by_ancestor(n, memo):
                    continue
                cands.append((n, kind))
        exts = bulk_extents([n for n, _ in cands])
        out = []
        cells = []  # table cells: one row = one target, merged below
        for (n, kind), e in zip(cands, exts):
            if e is None:  # no pipelined answer: ask this one directly
                g = n.get_extents(Atspi.CoordType.WINDOW)
                e = (g.x, g.y, g.width, g.height)
            ex, ey, ew, eh = e
            if kind == 2 and (ew > MAX_GENERIC[0] or eh > MAX_GENERIC[1]):
                continue
            x, y = ex + ox, ey + oy
            x2, y2 = min(x + ew, cx + cw), min(y + eh, cy + ch)
            x, y = max(x, cx), max(y, cy)
            if x2 - x >= MIN_W and y2 - y >= MIN_H:
                (cells if kind == 3 else out).append((x, y, x2 - x, y2 - y))
        out += merge_rows(cells)
        return out, len(cands)
    except Exception:
        return None


def embedded_roots(win, budget=60):
    """Parts of the window drawn by another process (a WebKit web view in a GTK or
    Tauri app), as (root, dx, dy). A Collection query stays inside one process, so
    these need their own. dx, dy move the root onto the spot its host gave it, in
    case that process counts positions from its own corner."""
    own = win.app.bus_name
    roots, queue, seen = [], [win], 0
    while queue and seen < budget:
        n = queue.pop(0)
        seen += 1
        try:
            role = n.get_role()
            if n is not win and role in (Atspi.Role.DOCUMENT_WEB, Atspi.Role.DOCUMENT_FRAME):
                continue  # a page in this process: Collection already covers it
            if role in PRUNE_HIDDEN and not n.get_state_set().contains(Atspi.StateType.SHOWING):
                continue
            for i in range(min(n.get_child_count(), MAX_CHILDREN)):
                c = n.get_child_at_index(i)
                if c is None:
                    continue
                if c.app is not None and c.app.bus_name != own:
                    pe, ce = n.get_extents(Atspi.CoordType.WINDOW), c.get_extents(Atspi.CoordType.WINDOW)
                    roots.append((c, pe.x - ce.x, pe.y - ce.y))
                else:
                    queue.append(c)
        except Exception:
            continue
    if queue and seen >= budget:
        print(f"hint-atspi: stopped looking for web views after {budget} nodes", file=sys.stderr)
    return roots


def read_tree(win, ox, oy, clip, layer=False):
    """-> (boxes, exposed) for the window, including web views run by other processes."""
    r = walk_fast(win, ox, oy, clip, layer)
    if r is None:
        return walk(win, ox, oy, clip, layer)  # walks across processes on its own
    boxes, exposed = r
    if layer:
        return r  # bars draw everything themselves
    try:
        for root, dx, dy in embedded_roots(win):
            sub = walk_fast(root, ox + dx, oy + dy, clip) or walk(root, ox + dx, oy + dy, clip)
            boxes, exposed = boxes + sub[0], exposed + sub[1]
    except Exception as ex:  # keep what the window itself gave
        print(f"hint-atspi: reading a web view failed: {ex}", file=sys.stderr)
    return boxes, exposed


def find_holes(win, ox, oy, clip):
    """Showing lists/toolbars/trees that expose no children at all (Ferdium's
    service rail). The caller fills just those rectangles with picture-based boxes."""
    holes = []
    try:
        col = win.get_collection_iface()
        if col is None:
            return holes
        states = Atspi.StateSet.new([Atspi.StateType.SHOWING, Atspi.StateType.SENSITIVE])
        cx, cy, cw, ch = clip
        hr = Atspi.MatchRule.new(states, Atspi.CollectionMatchType.ALL, None, Atspi.CollectionMatchType.ALL,
                                 list(HOLE_ROLES), Atspi.CollectionMatchType.ANY, None, Atspi.CollectionMatchType.ALL, False)
        for n in col.get_matches(hr, Atspi.CollectionSortOrder.CANONICAL, 50, True):
            if n.get_child_count() == 0:
                e = n.get_extents(Atspi.CoordType.WINDOW)
                x, y = max(e.x + ox, cx), max(e.y + oy, cy)
                x2, y2 = min(e.x + ox + e.width, cx + cw), min(e.y + oy + e.height, cy + ch)
                if x2 - x >= 24 and y2 - y >= 24:
                    holes.append((x, y, x2 - x, y2 - y))
    except Exception:
        pass
    return holes[:3]


def dedupe(rects):
    """Drop exact duplicates and the bigger of two boxes that cover the same thing
    (a link around text, an icon inside its button, slightly offset wrappers)."""
    rects = sorted(set(rects), key=lambda r: r[2] * r[3])
    keep, grid, C = [], {}, 64  # grid of 64 px cells: only nearby kept boxes are compared
    for r in rects:
        cells = [(i, j) for i in range(int(r[0]) // C, int(r[0] + r[2]) // C + 1)
                 for j in range(int(r[1]) // C, int(r[1] + r[3]) // C + 1)]
        redundant = False
        for cell in cells:
            for k in grid.get(cell, ()):
                ix = min(r[0] + r[2], k[0] + k[2]) - max(r[0], k[0])
                iy = min(r[1] + r[3], k[1] + k[3]) - max(r[1], k[1])
                if ix > 0 and iy > 0 and ix * iy >= 0.8 * k[2] * k[3] and r[2] * r[3] <= 4 * k[2] * k[3]:
                    redundant = True
                    break
            if redundant:
                break
        if not redundant:
            keep.append(r)
            for cell in cells:
                grid.setdefault(cell, []).append(r)
    return keep


def detect_params():
    """detect_* tuning from the user's wl-kbptr config (same knobs vision mode uses)."""
    p = dict(min_width=8, min_height=4, max_width=499, max_height=49,
             merge_x=3.5, merge_y=2.5, edge_low=70, edge_high=220)
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    try:
        cp.read(os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "wl-kbptr", "config"))
        for k in p:
            if cp.has_option("mode_floating", "detect_" + k):
                p[k] = float(cp.get("mode_floating", "detect_" + k))
    except Exception:
        pass
    return p


def vision_boxes(x, y, w, h, params, blank=(), timeout=None):
    """Picture-based boxes (edge detection, like wl-kbptr's detect) inside one window.

    Only used for windows that expose no fields. `blank` = rects of windows drawn
    above this one (ignored by the detector). Returns None on error (logged),
    [] when the picture simply has no edges.
    """
    try:
        import cv2, numpy as np
        cv2.setNumThreads(0)  # its worker threads leaked ~5 MB per press when called from short-lived threads
        ppm = subprocess.run(["grim", "-t", "ppm", "-s", "1", "-g", f"{x},{y} {w}x{h}", "-"],
                             capture_output=True, timeout=timeout or 2, check=True).stdout
        img = cv2.imdecode(np.frombuffer(ppm, np.uint8), cv2.IMREAD_GRAYSCALE)
        if img is None or abs(img.shape[1] - w) > 2 or abs(img.shape[0] - h) > 2:
            raise ValueError("screenshot size does not match the window")
        k = params
        edges = cv2.Canny(img, k["edge_low"], k["edge_high"])
        for (bx, by, bw, bh) in blank:  # covered by a window above: not ours to box
            edges[max(0, by - y):max(0, by - y + bh), max(0, bx - x):max(0, bx - x + bw)] = 0
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (int(k["merge_x"] * 2) + 1, int(k["merge_y"] * 2) + 1))
        edges = cv2.dilate(edges, kernel)
        cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        out = []
        for c in cnts:
            bx, by, bw, bh = cv2.boundingRect(c)
            if k["min_width"] <= bw <= k["max_width"] and k["min_height"] <= bh <= k["max_height"]:
                out.append((x + bx, y + by, min(bw, w - bx), min(bh, h - by)))
        return sorted(out, key=lambda r: (r[1], r[0]))  # top-to-bottom, so a cap drops the bottom
    except Exception as ex:
        print(f"hint-atspi: vision failed for window at {x},{y}: {ex}", file=sys.stderr)
        return None


def bar_boxes(x, y, w, h):
    """Picture-based boxes for a bar of solid pills over the wallpaper (quickshell).
    Plain edge detection fails there: the wallpaper's edges merge with the pills.
    The pill fill is the bar's most common exact color; boxes = what is drawn on it.
    Returns None on error (logged)."""
    try:
        import cv2, numpy as np
        ppm = subprocess.run(["grim", "-t", "ppm", "-s", "1", "-g", f"{x},{y} {w}x{h}", "-"],
                             capture_output=True, timeout=2, check=True).stdout
        img = cv2.imdecode(np.frombuffer(ppm, np.uint8), cv2.IMREAD_COLOR)
        if img is None or abs(img.shape[1] - w) > 2 or abs(img.shape[0] - h) > 2:
            raise ValueError("screenshot size does not match the bar")
        cols, cnt = np.unique(img.reshape(-1, 3), axis=0, return_counts=True)
        # Exact-ish match: a wal wallpaper can sit within a few shades of the pill color.
        fill = np.abs(img.astype(int) - cols[cnt.argmax()].astype(int)).max(axis=2) <= 3
        rows = np.nonzero(fill.sum(axis=1) >= 0.5 * fill.sum(axis=1).max())[0]
        y0, y1 = rows.min(), rows.max()  # the pills' height
        if y1 - y0 < 6:
            return []
        # A pill column shows fill above and below its text; close small gaps (round ends, badges).
        col = (fill[y0 + 1] | fill[y1 - 1]).astype(np.uint8)[None, :] * 255
        col = cv2.morphologyEx(col, cv2.MORPH_CLOSE, np.ones((1, 15), np.uint8))[0] > 0
        ink = np.zeros(fill.shape, np.uint8)
        ink[y0 + 2:y1 - 1] = (~fill[y0 + 2:y1 - 1] & col[None, :]) * 255
        ink = cv2.dilate(ink, cv2.getStructuringElement(cv2.MORPH_RECT, (9, 3)))  # letters -> words
        cnts, _ = cv2.findContours(ink, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        out = [(x + bx, y + by, bw, bh) for bx, by, bw, bh in map(cv2.boundingRect, cnts)
               if MIN_W <= bw <= 499 and bh >= MIN_H]  # wider = wallpaper taken for a pill
        return sorted(out, key=lambda r: r[0])
    except Exception as ex:
        print(f"hint-atspi: bar picture failed at {x},{y}: {ex}", file=sys.stderr)
        return None


def pick_win(apps, title, size):
    """The app window matching this Hyprland window/layer, or None if unsure."""
    wins = []
    for app in apps:
        for j in range(app.get_child_count()):
            w = app.get_child_at_index(j)
            if w is not None:
                wins.append(w)
    cand = []
    for w in wins:
        try:
            e = w.get_extents(Atspi.CoordType.WINDOW)
            same_size = (e.width == 0 and e.height == 0) or \
                (abs(e.width - size[0]) <= 2 and abs(e.height - size[1]) <= 2)
            if same_size and (len(wins) == 1 or not title or w.get_name() == title):
                cand.append(w)
        except Exception:
            pass
    return cand[0] if len(cand) == 1 else None


def main(bar_only=None):
    """-> (exit code, output text). bar_only=None reads --bar / HINT_BAR."""
    if bar_only is None:
        bar_only = "--bar" in sys.argv[1:] or os.environ.get("HINT_BAR") == "1"

    if os.environ.get("MANGO_INSTANCE_SIGNATURE") and not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        monitors, all_clients, active, all_layers = mango_many()
    else:
        monitors, all_clients, active, all_layers = hypr_many("monitors", "clients", "activewindow", "layers")
    target_mon = next((m for m in monitors if m["focused"]), None)
    if target_mon is None:
        return 3, ""
    ws = target_mon["activeWorkspace"]["id"]
    clients = [c for c in all_clients
               if c["mapped"] and not c["hidden"] and c["workspace"]["id"] == ws and c["monitor"] == target_mon["id"]]
    # Fullscreen hides the rest of the workspace; FOCUS_ONLY=1 forces the same.
    if active and (active.get("fullscreen") or os.environ.get("FOCUS_ONLY") == "1"):
        clients = [c for c in clients if c["address"] == active.get("address")]
        with_layers = False
    else:
        with_layers = True
    if bar_only:
        clients, with_layers = [], True
    # Focused window first: it decides vision vs. fields and must not lose to a big window's budget.
    clients.sort(key=lambda c: not (active and c["address"] == active.get("address")))
    layers = []
    if isinstance(all_layers, dict):
        for lvl in all_layers.get(target_mon["name"], {}).get("levels", {}).values():
            layers += lvl

    Atspi.init()
    desk = Atspi.get_desktop(0)
    by_pid = {}
    for i in range(desk.get_child_count()):
        app = desk.get_child_at_index(i)
        if app is None:
            continue
        try:
            by_pid.setdefault(app.get_process_id(), []).append(app)
        except Exception:
            pass
    if isinstance(all_layers, list):  # mango
        layers = mango_layers([l["name"] for l in all_layers if l.get("monitor") == target_mon["name"]
                               and l.get("layer") in ("top", "overlay")], by_pid, target_mon["width"])

    # Drop boxes hidden under a window drawn above them (floating sits above tiled;
    # among floating windows a lower focusHistoryID is more recent, i.e. above).
    def fh(c):
        v = c.get("focusHistoryID", -1)
        return v if v >= 0 else 10**6  # never focused = bottom of the stack

    def above(c):
        return [(o["at"], o["size"]) for o in clients if o is not c and o["floating"]
                and (not c["floating"] or fh(o) < fh(c))]

    def visible(box, host):
        if host is None:
            return True  # layer surface (bar)
        cx, cy = box[0] + box[2] / 2, box[1] + box[3] / 2
        return not any(a[0][0] <= cx < a[0][0] + a[1][0] and a[0][1] <= cy < a[0][1] + a[1][1]
                       for a in above(host))

    items = []  # (box, owning client or None for layers); order = priority when capping
    params = detect_params()

    def vision_for(c):
        a = above(c)
        return vision_boxes(c["at"][0], c["at"][1], c["size"][0], c["size"][1], params,
                            [(o[0][0], o[0][1], o[1][0], o[1][1]) for o in a])

    def walk_layer(l):
        apps = by_pid.get(l.get("pid"))
        w = pick_win(apps, "", (l["w"], l["h"])) if apps else None
        if w is None:
            return []
        lx, ly = l["x"] + target_mon["x"], l["y"] + target_mon["y"]
        clip = (lx, ly, l["w"], l["h"])
        boxes, exposed = read_tree(w, lx, ly, clip, layer=True)
        if not exposed and not NO_VISION:  # quickshell bars expose only an empty frame
            boxes = bar_boxes(lx, ly, l["w"], l["h"]) or vision_boxes(lx, ly, l["w"], l["h"], params) or []
        return boxes[:MAX_PER_SOURCE]

    def walk_client(c):
        apps = by_pid.get(c["pid"])
        x, y = c["at"]
        sx, sy = c["size"]
        w = pick_win(apps, c["title"], (sx, sy)) if apps else None
        if w is None:  # unsure which accessible window this is: say so, invent nothing
            print(f"hint-atspi: no unique accessible window for {c['class']!r} {c['title']!r}", file=sys.stderr)
            return None
        clip = (x, y, sx, sy)
        # Empty lists/toolbars: picture detection starts now, inside just those
        # rectangles, while the Collection query below is still waiting.
        hole_futs = []
        if not NO_VISION:
            blank = [(o[0][0], o[0][1], o[1][0], o[1][1]) for o in above(c)]
            hole_futs = [hole_pool.submit(vision_boxes, hx, hy, hw, hh, params, blank)
                         for (hx, hy, hw, hh) in find_holes(w, x, y, clip)]
        boxes, exposed = read_tree(w, x, y, clip)
        extra = []
        for f in hole_futs:
            try:
                extra += f.result() or []
            except Exception:
                pass
        return (extra + boxes)[:MAX_PER_SOURCE], exposed  # hole boxes first: they are few and nothing else covers them

    # Everything slow runs at once: D-Bus walks mostly wait on their apps, and
    # windows that never registered on the accessibility bus (terminals) need
    # pictures anyway, so grim/OpenCV start now instead of after the walks.
    pool = ThreadPoolExecutor(max_workers=6)
    hole_pool = ThreadPoolExecutor(max_workers=3)
    bar_futs = [pool.submit(walk_layer, l) for l in layers] if with_layers else []
    futs = {}
    for c in clients:
        if by_pid.get(c["pid"]):
            futs[c["address"]] = pool.submit(walk_client, c)
        elif not NO_VISION:
            futs[c["address"]] = pool.submit(vision_for, c)

    def get(fut):  # waits for the real answer; a hung app is the daemon watchdog's problem, loudly
        try:
            return fut.result()
        except Exception as ex:
            print(f"hint-atspi: read failed: {ex}", file=sys.stderr)
            return None

    # Bar first: it is cheap and must never lose to a busy window's slots.
    for f in bar_futs:
        items += [(b, None) for b in (get(f) or [])]
    for c in clients:
        x, y = c["at"]
        sx, sy = c["size"]
        f = futs.get(c["address"])
        got = get(f) if f is not None else None
        if by_pid.get(c["pid"]):
            if got is None:
                continue  # the read failed or the window is ambiguous: logged above, nothing invented
            boxes, exposed = got
            if not exposed and not NO_VISION:
                boxes = (vision_for(c) or [])[:MAX_PER_SOURCE]  # the tree exposes no fields at all
        else:
            boxes = (got or [])[:MAX_PER_SOURCE]  # never on the accessibility bus: pictures, this window only
        items += [(b, c) for b in boxes]
    pool.shutdown(wait=False, cancel_futures=True)
    hole_pool.shutdown(wait=False, cancel_futures=True)

    items = [(b, h) for b, h in items if visible(b, h)][:800]  # input cap keeps dedupe cheap
    rank = {}
    for i, (b, _) in enumerate(items):
        rank.setdefault(b, i)
    boxes = sorted(dedupe([b for b, _ in items]), key=lambda b: rank[b])[:MAX_RECTS]  # bar/focused first

    # hyprctl monitor width/height are physical pixels; everything else is logical.
    scale = 1 if target_mon.get("logical") else target_mon.get("scale") or 1
    mw, mh = target_mon["width"] / scale, target_mon["height"] / scale
    if target_mon.get("transform", 0) % 2:
        mw, mh = mh, mw
    mx, my = target_mon["x"], target_mon["y"]
    res = []
    for (x, y, w, h) in boxes:
        x, y = x - mx, y - my
        x2, y2 = min(x + w, mw), min(y + h, mh)
        x, y = max(x, 0), max(y, 0)
        if x2 - x >= MIN_W and y2 - y >= MIN_H:
            res.append((round(x2 - x), round(y2 - y), round(x), round(y)))
    if not res:
        return 3, ""
    return 0, "".join(f"{w}x{h}+{x}+{y}\n" for w, h, x, y in res)


def serve(path):
    """Keep the heavy imports and the accessibility connection warm; answer
    "full" / "bar" requests on a private unix socket. A cold start costs ~0.3 s
    of Python, gi and OpenCV loading, which is most of the SUPER+D delay."""
    import socket, fcntl, threading
    run_dir = os.path.realpath(os.environ["XDG_RUNTIME_DIR"])
    if os.path.dirname(os.path.realpath(path)) != run_dir:
        print("hint-atspi: socket must live directly in $XDG_RUNTIME_DIR", file=sys.stderr)
        return 2
    lock = open(path + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 1  # another daemon is starting or running
    probe = socket.socket(socket.AF_UNIX)
    probe.settimeout(0.5)
    try:
        probe.connect(path)
        return 1  # a live daemon already answers
    except socket.timeout:
        return 1  # alive but busy
    except OSError:
        pass  # nothing there, or a stale socket file
    finally:
        probe.close()
    srv = socket.socket(socket.AF_UNIX)
    os.umask(0o177)  # socket is for this user only (it sits in $XDG_RUNTIME_DIR, mode 0700)
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    srv.bind(path)
    srv.listen(4)
    try:
        import cv2, numpy  # noqa: F401  (warm the import; early requests wait in the backlog)
    except Exception:
        pass
    # Apps send accessibility events all the time; nothing reads them unless this loop
    # does, so they would pile up in memory for as long as the daemon lives.
    events = GLib.MainContext.default()
    try:
        import ctypes
        trim = ctypes.CDLL("libc.so.6").malloc_trim
    except Exception:
        trim = None
    srv.settimeout(1.0)
    while True:
        while events.pending():
            events.iteration(False)
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        with conn:
            try:
                conn.settimeout(2.0)
                parts = conn.recv(300).split(b"\n")[0].split()
                req = parts[0] if parts else b""
                if req not in (b"full", b"bar"):
                    continue
                ver = os.environ.get("HINT_ATSPI_VER")
                if len(parts) > 1 and ver is not None and parts[1].decode(errors="replace") != ver:
                    os._exit(0)  # older build than the caller: exit, the caller starts a new one
                box = []

                def work():
                    try:
                        box.append(main(bar_only=req == b"bar"))
                    except Exception as ex:
                        print(f"hint-atspi: {ex}", file=sys.stderr)
                        box.append(None)  # stale Hyprland environment or broken bus: restart

                t = threading.Thread(target=work, daemon=True)
                t.start()
                t.join(2.6)  # a hung app must not freeze every later press
                if not box or box[0] is None:
                    if not box:
                        print("hint-atspi: request took over 2.6 s, exiting", file=sys.stderr)
                    conn.sendall(b"3\n")
                    os._exit(0)  # the next SUPER+D starts a fresh daemon
                rc, text = box[0]
                conn.sendall(f"{rc}\n{text}".encode())
            except OSError:
                pass
        if trim:
            trim(0)  # hand memory freed by this press back to the system, after the reply


if __name__ == "__main__":
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "--serve":
            sys.exit(serve(os.environ.get("HINT_ATSPI_SOCK") or os.path.join(os.environ["XDG_RUNTIME_DIR"], "hint-atspi.sock")))
        rc, text = main()
        sys.stdout.write(text)
        sys.exit(rc)
    except Exception as ex:
        print(f"hint-atspi: {ex}", file=sys.stderr)
        sys.exit(3)
