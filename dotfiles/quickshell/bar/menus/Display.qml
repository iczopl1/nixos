import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Monitor manager: a screen map you drag, plus controls for the picked screen.
// Fixed gray look copied from the SUPER-tap launcher (AppIcons.qml); no wal colors.
// Reads `wlr-randr --json` when opened (nothing runs while closed); applies with `wlr-randr`.
// Changes last until the compositor restarts; the permanent layout stays in
// ~/.config/mango/mango-monitors.conf (monitor_rule lines).
Rectangle {
    id: root

    signal close

    property var outs: []        // parsed `wlr-randr --json`
    property string sel: ""      // picked output name
    readonly property var out: outs.find(o => o.name === sel) || null
    readonly property var on: outs.filter(o => o.enabled)

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property color fg: Theme.sw("#ECEFF4")
    readonly property color dim: Theme.sw("#777777")
    readonly property color accent: Theme.sw("#E6E6E6")   // active pill / picked screen
    readonly property color textOnAccent: Theme.sw("#000000")
    readonly property color panel: Theme.sw("#3A3A3A")    // buttons
    readonly property color panelHover: Theme.sw("#5A5A5A")
    readonly property color tile: Theme.sw("#303030")

    function open() {
        if (!probe.running)
            probe.running = true;
        keys.forceActiveFocus();
    }

    Process {
        id: probe
        command: ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.outs = JSON.parse(text);
                } catch (e) {
                    root.outs = [];
                }
                if (!root.out)
                    root.sel = root.on.length ? root.on[0].name : (root.outs.length ? root.outs[0].name : "");
            }
        }
    }

    // wlr-randr applies instantly; re-read a moment later so the map shows the result
    Timer {
        id: reread
        interval: 500
        onTriggered: if (!probe.running) probe.running = true
    }

    function run(args) {
        Quickshell.execDetached(["wlr-randr", ...args]);
        reread.restart();
    }

    function hz(r) {
        return String(+r.toFixed(2));
    }

    function curMode(o) {
        return o.modes.find(m => m.current) || o.modes.find(m => m.preferred) || o.modes[0];
    }

    // size in layout pixels: mode size, swapped when turned 90/270, divided by scale
    function size(o) {
        const m = curMode(o);
        const turned = /90|270/.test(o.transform);
        return { w: Math.round((turned ? m.height : m.width) / o.scale),
                 h: Math.round((turned ? m.width : m.height) / o.scale) };
    }

    // Mango needs positive coordinates (XWayland click bug): shift so the top left output sits at 0,0
    function applyPositions(pos) {
        const v = Object.values(pos);
        const mx = Math.min(...v.map(p => p.x));
        const my = Math.min(...v.map(p => p.y));
        const args = [];
        for (const n of Object.keys(pos))
            args.push("--output", n, "--pos", Math.round(pos[n].x - mx) + "," + Math.round(pos[n].y - my));
        run(args);
    }

    // Snap a dragged screen (layout px, top left lx,ly): edges pull to the other screens' edges
    // within th px, and it is pushed out of any screen it would overlap.
    function snap(o, lx, ly, th) {
        const s = size(o);
        let x = lx, y = ly, dx = th, dy = th;
        for (const r of on) {
            if (r.name === o.name)
                continue;
            const q = size(r), rx = r.position.x, ry = r.position.y;
            for (const c of [rx + q.w, rx - s.w, rx, rx + q.w - s.w])
                if (Math.abs(c - lx) < dx) { dx = Math.abs(c - lx); x = c; }
            for (const c of [ry + q.h, ry - s.h, ry, ry + q.h - s.h])
                if (Math.abs(c - ly) < dy) { dy = Math.abs(c - ly); y = c; }
        }
        for (const r of on) {
            if (r.name === o.name)
                continue;
            const q = size(r), rx = r.position.x, ry = r.position.y;
            if (x < rx + q.w && x + s.w > rx && y < ry + q.h && y + s.h > ry) {
                const opts = [{ x: rx - s.w, y: y }, { x: rx + q.w, y: y }, { x: x, y: ry - s.h }, { x: x, y: ry + q.h }];
                let best = opts[0], bd = 1e9;
                for (const c of opts) {
                    const d = Math.abs(c.x - x) + Math.abs(c.y - y);
                    if (d < bd) { bd = d; best = c; }
                }
                x = best.x;
                y = best.y;
            }
        }
        return { x: x, y: y };
    }

    function drop(o, lx, ly, th) {
        const p = snap(o, lx, ly, th);
        const pos = {};
        for (const q of on)
            pos[q.name] = { x: q.position.x, y: q.position.y };
        pos[o.name] = p;
        applyPositions(pos);
    }

    // every screen on, side by side in their current left-to-right order, tops aligned
    function extend() {
        const list = outs.slice().sort((a, b) => (a.enabled ? a.position.x : 1e9) - (b.enabled ? b.position.x : 1e9));
        const args = [];
        let x = 0;
        for (const o of list) {
            args.push("--output", o.name, "--on", "--pos", x + ",0");
            x += size(o).w;
        }
        run(args);
    }

    function only(name) {
        const args = ["--output", name, "--on", "--pos", "0,0"];
        for (const o of outs)
            if (o.name !== name)
                args.push("--output", o.name, "--off");
        run(args);
    }

    // small clickable pill; `active` marks the current value
    component Pill: Rectangle {
        id: pill
        property alias text: label.text
        property bool active: false
        property bool enabled: true
        signal clicked
        implicitWidth: label.implicitWidth + 22
        implicitHeight: 30
        radius: 6
        opacity: enabled ? 1 : 0.35
        color: active ? root.accent : (area.containsMouse && enabled ? root.panelHover : root.panel)
        Text {
            id: label
            anchors.centerIn: parent
            color: pill.active ? root.textOnAccent : root.fg
            font { family: root.font; pixelSize: 13; bold: pill.active }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: pill.enabled
            onClicked: pill.clicked()
        }
    }

    component Heading: Text {
        color: root.dim
        font { family: root.font; pixelSize: 11; letterSpacing: 1; capitalization: Font.AllUppercase }
    }

    width: 820
    height: body.implicitHeight + 40
    radius: 20
    color: Theme.sw("#F2262626")
    border { width: 2; color: Theme.sw("#4D4D4D") }

    MouseArea { anchors.fill: parent }  // clicks inside must not close the overlay

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
    }

    Column {
        id: body
        x: 20; y: 20
        width: parent.width - 40
        spacing: 14

        Row {
            width: parent.width
            Text {
                text: "Displays"
                color: root.fg
                font { family: root.font; pixelSize: 17; bold: true }
            }
            Item { width: parent.width - 330; height: 1 }
            Text {
                text: "drag a screen to move it"
                color: root.dim
                font { family: root.font; pixelSize: 12 }
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // the screen map
        Rectangle {
            id: map
            width: parent.width
            height: 250
            radius: 6
            color: root.tile
            border { width: 2; color: Theme.sw("#5A5A5A") }
            clip: true

            readonly property real minX: root.on.length ? Math.min(...root.on.map(o => o.position.x)) : 0
            readonly property real minY: root.on.length ? Math.min(...root.on.map(o => o.position.y)) : 0
            readonly property real maxX: root.on.length ? Math.max(...root.on.map(o => o.position.x + root.size(o).w)) : 1
            readonly property real maxY: root.on.length ? Math.max(...root.on.map(o => o.position.y + root.size(o).h)) : 1
            // layout px -> map px; room around the edge so a screen can be dragged out past the others
            readonly property real k: Math.min((width - 120) / Math.max(1, maxX - minX), (height - 70) / Math.max(1, maxY - minY), 0.25)
            readonly property real ox: (width - (maxX - minX) * k) / 2
            readonly property real oy: (height - (maxY - minY) * k) / 2 - 10

            Text {
                visible: root.outs.length === 0
                anchors.centerIn: parent
                text: "No screens found (wlr-randr failed)"
                color: root.dim
                font { family: root.font; pixelSize: 13 }
            }

            Repeater {
                model: root.on
                Rectangle {
                    id: tile
                    required property var modelData
                    readonly property var sz: root.size(modelData)
                    readonly property bool picked: root.sel === modelData.name
                    width: sz.w * map.k
                    height: sz.h * map.k
                    x: map.ox + (modelData.position.x - map.minX) * map.k
                    y: map.oy + (modelData.position.y - map.minY) * map.k
                    radius: 6
                    color: picked ? root.panelHover : Theme.sw("#303030")
                    border { width: 2; color: picked ? root.accent : Theme.sw("#5A5A5A") }
                    z: drag.active ? 2 : 0
                    readonly property real snapTh: 30 / map.k   // 30 map px, in layout px
                    function layoutX() { return (x - map.ox) / map.k + map.minX; }
                    function layoutY() { return (y - map.oy) / map.k + map.minY; }
                    // while dragging, the box jumps to where it would snap (live preview)
                    property bool snapping: false
                    function liveSnap() {
                        if (!drag.active || snapping)
                            return;
                        snapping = true;
                        const p = root.snap(modelData, layoutX(), layoutY(), snapTh);
                        x = map.ox + (p.x - map.minX) * map.k;
                        y = map.oy + (p.y - map.minY) * map.k;
                        snapping = false;
                    }
                    onXChanged: liveSnap()
                    onYChanged: liveSnap()
                    Behavior on x { enabled: !drag.active; NumberAnimation { duration: 120 } }
                    Behavior on y { enabled: !drag.active; NumberAnimation { duration: 120 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.name
                            color: root.fg
                            font { family: root.font; pixelSize: 14; bold: true }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            readonly property var m: root.curMode(tile.modelData)
                            text: m.width + "x" + m.height + " @ " + root.hz(m.refresh)
                            color: Theme.sw("#BBBBBB")
                            font { family: root.font; pixelSize: 11 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: root.sel = tile.modelData.name
                        drag {
                            id: drag
                            target: tile
                            onActiveChanged: if (!drag.active)
                                root.drop(tile.modelData, tile.layoutX(), tile.layoutY(), tile.snapTh)
                        }
                    }
                }
            }

            // screens that are off sit along the bottom edge
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                spacing: 8
                Repeater {
                    model: root.outs.filter(o => !o.enabled)
                    Pill {
                        required property var modelData
                        text: modelData.name + "  (off)"
                        active: root.sel === modelData.name
                        onClicked: root.sel = modelData.name
                    }
                }
            }
        }

        // controls for the picked screen
        Column {
            width: parent.width
            spacing: 10
            visible: root.out !== null

            Row {
                spacing: 10
                Heading { text: "Power"; width: 64; anchors.verticalCenter: parent.verticalCenter }
                Pill {
                    text: root.out && root.out.enabled ? "On" : "Off"
                    active: root.out ? root.out.enabled : false
                    enabled: !(root.out && root.out.enabled && root.on.length < 2)  // never turn off the last screen
                    onClicked: root.run(["--output", root.sel, "--toggle"])
                }
            }

            Row {
                spacing: 10
                Heading { text: "Scale"; width: 64; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: [1, 1.25, 1.5, 1.75, 2]
                    Pill {
                        required property var modelData
                        text: String(modelData)
                        active: root.out ? root.out.scale === modelData : false
                        onClicked: root.run(["--output", root.sel, "--scale", String(modelData)])
                    }
                }
            }

            Row {
                spacing: 10
                Heading { text: "Rotate"; width: 64; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["normal", "90", "180", "270"]
                    Pill {
                        required property var modelData
                        text: modelData === "normal" ? "0°" : modelData + "°"
                        active: root.out ? root.out.transform === modelData : false
                        onClicked: root.run(["--output", root.sel, "--transform", modelData])
                    }
                }
            }

            Row {
                spacing: 10
                Heading { text: "Mode"; width: 64; topPadding: 8 }
                Flow {
                    width: parent.width - 74
                    spacing: 8
                    Repeater {
                        model: root.out ? root.out.modes.slice(0, 14) : []
                        Pill {
                            required property var modelData
                            text: modelData.width + "x" + modelData.height + " @ " + root.hz(modelData.refresh)
                            active: modelData.current
                            onClicked: root.run(["--output", root.sel, "--mode", modelData.width + "x" + modelData.height + "@" + modelData.refresh])
                        }
                    }
                }
            }
        }

        Row {
            spacing: 10
            Pill {
                text: "Extend all"
                enabled: root.outs.length > 1
                onClicked: root.extend()
            }
            Pill {
                text: root.out ? "Only " + root.out.name : "Only this"
                enabled: root.outs.length > 1 && root.out !== null
                onClicked: root.only(root.sel)
            }
            Pill { text: "Close"; onClicked: root.close() }
        }

        Text {
            text: "Changes last until the compositor restarts."
            color: root.dim
            font { family: root.font; pixelSize: 11 }
        }
    }
}
