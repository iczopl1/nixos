import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// SUPER+D: Vimium-style hints. The overlay stays mapped (see-through, click-through)
// like the menus, so opening it is a repaint. Boxes come from hintd (one request on
// its socket) plus the bar's own items; a pick is sent back to hintd, which clicks.
// Live mode (experimental): the overlay re-reads hintd every frame, 16 ms (or as fast as hintd answers), keeps a box's
// label while the box stays put, and is click-through (mouse and wheel reach the apps; keys still go to the hints).
// Live mode: F1 pauses (every key goes to the apps); F1 or Esc resumes; Esc with hints on ends it (so does the live hotkey).
//   ab / 1ab left   2ab middle   3ab right   4ab press and hold, next pick drops   Esc cancels
// Toggle:  socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-hints-$WAYLAND_DISPLAY.sock
// Live:    socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-hints-live-$WAYLAND_DISPLAY.sock
Scope {
    id: root

    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string hintdPath: Quickshell.env("HINTD_SOCK") || runDir + "/hintd.sock"
    readonly property string letters: "qwertasdfgzxcv"   // one-letter labels, and the 2nd letter of two-letter ones (left hand)
    readonly property string firsts: "yuiophjklnm"       // 1st letter of two-letter labels (right hand)
    readonly property int pool: 420       // labels allocated once; a press only changes their properties
    readonly property color outline: "#ffd84a"

    property bool active: false
    property string mon: ""               // monitor hintd answered for
    property var boxes: []                // [{x, y, w, h, label}]
    property int labelLen: 1
    property string typed: ""
    property string button: "l"
    property bool holding: false
    property var lines: []
    property bool paused: false           // live: F1 hands every key back to the apps until F1 again
    property bool live: false             // experimental: refresh every liveMs
    property bool pending: false          // a first request is in flight
    readonly property int liveMs: 16
    property string boxSig: ""            // live: rects of the boxes on screen, to skip identical refreshes

    // Tag view and window count of every monitor. A change closes the overlay (not during a drag hold).
    readonly property string sig: Mango.monitors.map(m => m.name + (m.tags || []).map(t => (t.is_active ? "+" : "-") + t.client_count).join(",")).join("|")
    property string reqSig: ""            // sig when SUPER+D was pressed; a reply for an older view is dropped
    onSigChanged: {
        if (active && !holding && !live)
            close();
    }
    property double t0: 0
    property bool showTime: false          // toggled by the timing socket
    property int tookMs: 0

    function toggle() {
        if (active) {
            close();
            return;
        }
        live = false;
        request();
    }

    function toggleLive() {
        if (active) {
            close();
            return;
        }
        live = true;
        request();
    }

    function request() {
        t0 = Date.now();
        reqSig = sig;
        lines = [];
        pending = true;
        if (!live)
            stateReq.connected = true;
        boxReq.connected = true;
    }

    // A running drag-and-drop makes the compositor swallow the keyboard, so while a drag is held the keys come
    // from Mango binds (keymode "hintkeys", see mango-hintkeys.conf) through the key socket below.
    property string km: "default"
    function setKm(name) {
        if (km === name)
            return;
        km = name;
        Quickshell.execDetached(["mmsg", "dispatch", "setkeymode," + name]);
    }
    function setKeymode(on) {
        setKm(on ? "hintkeys" : "default");
    }

    function close() {
        setKeymode(false);
        liveTimer.stop();
        live = false;
        paused = false;
        pending = false;
        boxSig = "";
        active = false;
        typed = "";
        button = "l";
        boxes = [];
    }

    function label(i) {
        return labelLen === 1 ? letters[i] : firsts[Math.floor(i / letters.length)] + letters[i % letters.length];
    }

    // Label spot: top-left corner, centered on the top edge (the old wl-kbptr badge).
    // A label that would cover an earlier one moves to the first free spot: bottom edge,
    // a row above, a row below, then sideways. Estimated size: 9 px per letter, 10 px high (capitals 8 + 1 px box on each side).
    function nudge(list) {
        const lh = 10;
        const placed = [];
        for (const b of list) {
            const lw = 9 * b.label.length + 2;
            const x0 = Math.max(0, b.x - 2);
            const top = Math.max(0, b.y - lh / 2);
            const bot = Math.max(0, b.y + b.h - lh / 2);
            const spots = [[x0, top], [x0, bot], [x0, Math.max(0, top - lh)], [x0, bot + lh],
                [x0 + lw, top], [x0 + lw, bot], [Math.max(0, x0 - lw), top], [Math.max(0, x0 - lw), bot]];
            let at = spots[0];
            for (const s of spots) {
                if (!placed.some(p => s[0] < p[0] + p[2] && p[0] < s[0] + lw && s[1] < p[1] + lh && p[1] < s[1] + lh)) {
                    at = s;
                    break;
                }
            }
            b.lx = at[0];
            b.ly = at[1];
            placed.push([at[0], at[1], lw]);
        }
    }

    // Live refresh: a box that did not move keeps its label, new boxes take free labels, so a typed key stays meaningful.
    function relabel(list) {
        const need = Math.min(list.length, pool);
        if (labelLen === 1 && need > letters.length) {
            labelLen = 2;
            typed = "";
            boxes = [];
        }
        const key = b => b.x + "," + b.y + "," + b.w + "," + b.h;
        const old = {};
        for (const b of boxes)
            old[key(b)] = b.label;
        const used = {};
        const todo = [];
        for (const b of list) {
            const l = old[key(b)];
            if (l !== undefined && !used[l]) {
                b.label = l;
                used[l] = true;
            } else {
                todo.push(b);
            }
        }
        let i = 0;
        for (const b of todo) {
            while (used[label(i)])
                i++;
            b.label = label(i);
            used[b.label] = true;
        }
    }

    function open() {
        const refresh = live && active;
        if (!refresh && !pending)
            return;
        if (lines.length === 0 || (!live && sig !== reqSig)) {
            return;
        }
        pending = false;
        mon = lines[0];
        const list = [];
        const bar = BarTargets.rects(mon);
        for (const r of bar)
            list.push(r);
        for (let i = 1; i < lines.length && list.length < Math.min(pool, firsts.length * letters.length); i++) {
            const p = lines[i].split(" ");
            if (p.length === 4)
                list.push({ x: +p[0], y: +p[1], w: +p[2], h: +p[3] });
        }
        if (refresh) {
            const sg = list.map(b => b.x + "," + b.y + "," + b.w + "," + b.h).join(";");
            if (sg === boxSig)
                return;
            boxSig = sg;
            relabel(list);
            nudge(list);
            boxes = list;
            tookMs = Date.now() - t0;
            return;
        }
        if (list.length === 0) {
            live = false;
            return;
        }
        labelLen = list.length <= letters.length ? 1 : 2;
        for (let i = 0; i < list.length; i++)
            list[i].label = label(i);
        nudge(list);
        boxSig = list.map(b => b.x + "," + b.y + "," + b.w + "," + b.h).join(";");
        typed = "";
        button = "l";
        boxes = list;
        active = true;
        // Live mode never takes the keyboard from the compositor: its keys come from the Mango keymode binds,
        // so arrows, space, Home, End and the rest still reach the app.
        if (holding || live)
            setKeymode(true);
        tookMs = Date.now() - t0;
        if (Quickshell.env("HINTS_DEBUG"))
            console.log("hints: open in " + (Date.now() - t0) + " ms, " + list.length + " boxes");
    }

    function pick(b) {
        const x = Math.round(b.x + b.w / 2);
        const y = Math.round(b.y + b.h / 2);
        const kind = holding ? "d" : ({ "1": "n", "2": "r", "3": "m", "4": "x", "5": "h", "6": "d" }[button] || "l");
        const mm = mon;
        if (live) {
            // Live mode stays open (and click-through): click at once, keep refreshing, end on Esc or the hotkey.
            typed = "";
            button = "l";
            clickReq.pending = "click " + mm + " " + x + " " + y + " " + kind + "\n";
            clickReq.connected = true;
            return;
        }
        close();
        clickDelay.line = "click " + mm + " " + x + " " + y + " " + kind + "\n";
        clickDelay.restart();
    }

    // Let the compositor drop the overlay surface before the pointer moves, or the click lands on it.
    Timer {
        id: clickDelay
        property string line
        interval: 40
        onTriggered: {
            clickReq.pending = line;
            clickReq.connected = true;
        }
    }

    function key(e) {
        keyIn(e.key === Qt.Key_Escape ? "Escape" : e.key === Qt.Key_Backspace ? "BackSpace" : e.text);
    }

    // `k`: "Escape", "BackSpace", or one typed character.
    function keyIn(k) {
        if ((k === "F1" || (k === "Escape" && paused)) && live) {
            paused = !paused;
            setKm(paused ? "hintpause" : "hintkeys");
        } else if (paused) {
            // hintpause binds only F1 and Escape; nothing else arrives
        } else if (k === "Escape") {
            if (holding) {
                clickReq.pending = "release\n";
                clickReq.connected = true;
            }
            close();
        } else if (k === "BackSpace") {
            typed = typed.slice(0, -1);
        } else if (k >= "1" && k <= "6" && k.length === 1 && typed === "") {
            button = k;
        } else if (k.length === 1 && (labelLen === 2 && typed === "" ? firsts : letters).indexOf(k.toLowerCase()) >= 0) {
            typed += k.toLowerCase();
            if (typed.length === labelLen) {
                const hit = boxes.find(b => b.label === typed);
                if (hit)
                    pick(hit);
                else
                    typed = "";
            }
        }
    }

    // One key name per connection, sent by the Mango binds of keymode "hintkeys".
    SocketServer {
        id: keyServer
        active: true
        path: root.runDir + "/qs-menu-hints-key-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            parser: SplitParser {
                onRead: line => {
                    if (root.active)
                        root.keyIn(line.trim());
                }
            }
        }
    }

    // Next live request: liveMs after the last one started, or right away when hintd was slower than that.
    Timer {
        id: liveTimer
        onTriggered: {
            if (root.live && root.active)
                root.request();
        }
    }

    SocketServer {
        id: liveServer
        active: true
        path: root.runDir + "/qs-menu-hints-live-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            Component.onCompleted: root.toggleLive()
        }
    }

    SocketServer {
        id: toggleServer
        active: true
        path: root.runDir + "/qs-menu-hints-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            Component.onCompleted: root.toggle()
        }
    }

    // After a live reload the previous instance unlinks the path the new one just bound: bind again once it is gone.
    Timer {
        interval: 800
        running: true
        onTriggered: {
            toggleServer.active = false;
            toggleServer.active = true;
            liveServer.active = false;
            liveServer.active = true;
            timeServer.active = false;
            timeServer.active = true;
            keyServer.active = false;
            keyServer.active = true;
        }
    }

    // Every connection flips the on-screen timing readout (press to labels, in ms)
    SocketServer {
        id: timeServer
        active: true
        path: root.runDir + "/qs-menu-hints-time-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            Component.onCompleted: root.showTime = !root.showTime
        }
    }

    Socket {
        id: boxReq
        path: root.hintdPath
        onConnectedChanged: {
            if (connected) {
                write(root.live ? "boxes live\n" : "boxes\n");
                flush();
            } else {
                root.open();
                if (root.live && root.active) {
                    liveTimer.interval = Math.max(1, root.liveMs - (Date.now() - root.t0));
                    liveTimer.restart();
                } else if (root.live) {
                    root.live = false;
                    root.pending = false;
                }
            }
        }
        parser: SplitParser {
            onRead: line => root.lines.push(line)
        }
    }

    Socket {
        id: stateReq
        path: root.hintdPath
        onConnectedChanged: {
            if (connected) {
                write("state\n");
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => {
                root.holding = line === "hold";
                stateReq.connected = false;
            }
        }
    }

    Socket {
        id: clickReq
        property string pending: ""
        path: root.hintdPath
        onConnectedChanged: {
            if (connected) {
                write(pending);
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => {
                root.holding = line === "ok hold";
                if (root.live && root.active)
                    root.setKm(root.paused ? "hintpause" : "hintkeys");
                clickReq.connected = false;
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool mine: root.active && root.mon === modelData.name

            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region { item: win.mine && !root.live ? field : null }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: win.mine && !root.live ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "qs-hints"

            Item {
                id: field
                anchors.fill: parent
                focus: win.mine
                onFocusChanged: if (focus) forceActiveFocus()
                Keys.onPressed: e => {
                    root.key(e);
                    e.accepted = true;
                }

                // Mouse wheel or touchpad scroll closes the hints (not during a drag hold).
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: if (!root.holding) root.close()
                }

                Repeater {
                    model: root.pool

                    Item {
                        id: lab
                        required property int index
                        readonly property var b: root.boxes[index]
                        readonly property bool live: win.mine && b !== undefined && b.label.startsWith(root.typed)
                        readonly property string txt: b ? b.label.toUpperCase() : ""
                        // DejaVu Sans Bold capitals are 0.729 em tall.
                        readonly property int capH: Math.round(0.729 * face.font.pixelSize)
                        visible: live
                        x: b ? b.lx : 0
                        y: b ? b.ly : 0
                        width: Math.ceil(ink.tightBoundingRect.width) + 2
                        height: Math.max(capH, Math.ceil(ink.tightBoundingRect.height)) + 2

                        // Yellow box 1 px larger than the letters: as tall as the ink (capitals, plus the tails of J and Q),
                        // not the line height.
                        Rectangle {
                            anchors.fill: parent
                            color: root.outline
                        }

                        Text {
                            id: face
                            x: 1 - Math.floor(ink.tightBoundingRect.x)
                            y: 1 + lab.capH - baselineOffset
                            text: lab.txt
                            color: "#000000"
                            font.family: "DejaVu Sans"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0
                        }

                        // Ink width of the letters: the text item is wider (side gaps of the glyphs), which left more yellow on one side.
                        TextMetrics {
                            id: ink
                            font: face.font
                            text: lab.txt
                        }
                    }
                }

                Text {
                    visible: win.mine && root.showTime
                    anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                    text: root.tookMs + " ms · " + root.boxes.length + " boxes"
                    color: "#000000"
                    style: Text.Outline
                    styleColor: root.outline
                    font.family: "Barlow Condensed"
                    font.pixelSize: 20
                    font.bold: true
                }

                Text {
                    visible: win.mine && root.holding
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 40 }
                    text: "DROP: PICK THE TARGET"
                    color: "#000000"
                    style: Text.Outline
                    styleColor: root.outline
                    font.family: "Barlow Condensed"
                    font.pixelSize: 20
                    font.bold: true
                }
            }
        }
    }
}
