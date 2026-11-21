import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Month calendar that drops under the clock. Monday first, ISO week numbers,
// dots under days that have events, an agenda for the picked day, and a small
// form to add events. Events live in ~/.local/share/quickshell-calendar/events.json
// (import .ics files with scripts/import-ics.py).
//
// It is a layer window, not a popup, so it can take the keyboard: Escape closes
// (or cancels the form first), and the form can be typed into.
PanelWindow {
    id: root

    property Item target: null       // the clock the window hangs from
    property bool clockHovered: false
    property int shift: 0            // months away from the current one
    property date picked: new Date() // agenda day
    property bool adding: false      // the form is open (new event or an edit)
    property var viewing: null       // {ev, start, end, allDay} of the occurrence whose details show

    // ---------------------------------------------------------------- store
    readonly property string dir: Quickshell.env("HOME") + "/.local/share/quickshell-calendar"
    property var events: []

    FileView {
        id: store
        path: root.dir + "/events.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(store.text());
                root.events = Array.isArray(d) ? d : [];
            } catch (e) {
                root.events = [];
            }
        }
        onLoadFailed: root.events = []
    }

    function save(list) {
        events = list;
        Quickshell.execDetached(["mkdir", "-p", dir]);
        store.setText(JSON.stringify(list, null, 1));
    }

    function addEvent(ev) {
        save(events.concat([ev]));
    }

    function removeEvent(uid, startIso) {
        save(events.filter(e => !(e.uid === uid && e.start === startIso)));
    }

    function replaceEvent(uid, startIso, ev) {
        save(events.map(e => (e.uid === uid && e.start === startIso) ? ev : e));
    }

    // drop one occurrence of a repeating event
    function skipOccurrence(uid, startIso, dayKey) {
        save(events.map(e => (e.uid === uid && e.start === startIso)
            ? Object.assign({}, e, { exdate: (e.exdate || []).concat([dayKey]) }) : e));
    }

    function describeRule(r) {
        if (!r) return "";
        const unit = { DAILY: "day", WEEKLY: "week", MONTHLY: "month", YEARLY: "year" }[r.freq] || "?";
        const every = (r.interval || 1) > 1 ? "Every " + r.interval + " " + unit + "s" : "Every " + unit;
        const days = r.byday && r.byday.length ? " on " + r.byday.join(", ") : "";
        const cnt = r.count ? ", " + r.count + " times" : "";
        const until = r.until ? ", until " + r.until.slice(0, 10) : "";
        return every + days + cnt + until;
    }

    // ------------------------------------------------------------ import / export
    property bool ioOpen: false       // the import path row is showing
    property string ioStatus: ""

    // newest .ics in Downloads, offered as the import path
    Process {
        id: findIcs
        command: ["sh", "-c", "ls -t \"$HOME\"/Downloads/*.ics 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: if (!ioIn.text) ioIn.text = text.trim()
        }
    }
    Process {
        id: importer
        stdout: StdioCollector { id: impOut }
        stderr: StdioCollector { id: impErr }
        onExited: code => {
            root.ioStatus = code === 0 ? impOut.text.trim() : "Import failed: " + (impErr.text.trim().split("\n").pop() || "see the file path");
            if (code === 0) root.ioOpen = false;
        }
    }
    Process {
        id: exporter
        stdout: StdioCollector { id: expOut }
        stderr: StdioCollector { id: expErr }
        onExited: code => {
            root.ioStatus = code === 0 ? "Saved " + expOut.text.trim().replace(Quickshell.env("HOME"), "~")
                                       : "Export failed: " + (expErr.text.trim().split("\n").pop() || "no events yet?");
        }
    }

    function runImport() {
        const path = ioIn.text.trim();
        if (!path) { ioStatus = "Type the path of an .ics file"; return; }
        ioStatus = "Importing…";
        importer.command = ["python3", "-I", Quickshell.shellPath("scripts/import-ics.py"), path];
        importer.running = true;
    }
    function runExport() {
        ioStatus = "Exporting…";
        exporter.command = ["python3", "-I", Quickshell.shellPath("scripts/export-ics.py")];
        exporter.running = true;
    }
    function toggleImport() {
        ioOpen = !ioOpen;
        ioStatus = "";
        if (ioOpen) findIcs.running = true;
    }

    // ------------------------------------------------------------ date maths
    function pad(n) { return String(n).padStart(2, "0"); }
    function key(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
    function addDays(d, n) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds());
    }
    function parseStart(ev) {
        // all-day "YYYY-MM-DD" is local midnight; otherwise ISO (Z = UTC, none = local)
        if (ev.start.length === 10) {
            const p = ev.start.split("-");
            return new Date(+p[0], +p[1] - 1, +p[2]);
        }
        return new Date(ev.start);
    }
    function parseEnd(ev, s) {
        if (!ev.end) return ev.allDay ? addDays(s, 1) : new Date(s.getTime() + 3600000);
        if (ev.end.length === 10) {
            const p = ev.end.split("-");
            return new Date(+p[0], +p[1] - 1, +p[2]);
        }
        return new Date(ev.end);
    }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }

    // start times of one event before `we`; recurrence is expanded in local
    // wall-clock time, so a 09:00 event stays at 09:00 across DST
    function starts(ev, s, we) {
        const r = ev.rrule;
        if (!r) return [s];
        const out = [];
        const until = r.until ? (r.until.length === 10 ? parseStart({ start: r.until }) : new Date(r.until)) : null;
        const gone = ev.exdate || [];
        const step = r.interval > 0 ? r.interval : 1;
        let n = 0;
        let go = true;
        const add = d => {
            if (until && d > until) { go = false; return; }
            if (++n > 5000 || (r.count && n > r.count)) { go = false; return; }
            if (!gone.includes(key(d))) out.push(d);
        };
        const at = (y, m, d) => new Date(y, m, d, s.getHours(), s.getMinutes(), s.getSeconds());
        if (r.freq === "DAILY") {
            for (let d = s; go && d < we; d = at(d.getFullYear(), d.getMonth(), d.getDate() + step)) add(d);
        } else if (r.freq === "WEEKLY") {
            const names = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
            const offs = (r.byday && r.byday.length ? r.byday : [names[(s.getDay() + 6) % 7]])
                .map(x => names.indexOf(x)).filter(x => x >= 0).sort((a, b) => a - b);
            const w0 = at(s.getFullYear(), s.getMonth(), s.getDate() - ((s.getDay() + 6) % 7));
            for (let k = 0; go; k++) {
                const w = at(w0.getFullYear(), w0.getMonth(), w0.getDate() + 7 * step * k);
                if (w >= we) break;
                for (const o of offs) {
                    const d = at(w.getFullYear(), w.getMonth(), w.getDate() + o);
                    if (d < s) continue;
                    add(d);
                    if (!go) break;
                }
            }
        } else if (r.freq === "MONTHLY" || r.freq === "YEARLY") {
            const mstep = r.freq === "YEARLY" ? 12 * step : step;
            for (let k = 0; go; k++) {
                const d = at(s.getFullYear(), s.getMonth() + k * mstep, s.getDate());
                if (d >= we) break;
                if (d.getDate() !== s.getDate()) continue;   // 31st in a 30-day month
                add(d);
            }
        } else {
            return [s];
        }
        return out;
    }

    // "YYYY-MM-DD" -> [{ev, start, end, allDay}] for the 6 weeks on screen
    readonly property var dayMap: {
        const map = {};
        const ws = gridStart;
        const we = addDays(ws, 42);
        for (const ev of events) {
            if (!ev.start) continue;
            const s = parseStart(ev);
            if (isNaN(s.getTime())) continue;
            const dur = parseEnd(ev, s) - s;
            for (const os of starts(ev, s, we)) {
                const oe = new Date(os.getTime() + dur);
                if (oe <= ws && !(dur === 0 && os >= ws)) continue;
                let d = new Date(os.getFullYear(), os.getMonth(), os.getDate());
                do {
                    if (d >= ws && d < we) {
                        const k = key(d);
                        (map[k] = map[k] || []).push({ ev: ev, start: os, end: oe, allDay: !!ev.allDay });
                    }
                    d = addDays(d, 1);
                } while (d < oe);
            }
        }
        for (const k in map)
            map[k].sort((a, b) => (b.allDay - a.allDay) || (a.start - b.start));
        return map;
    }
    readonly property var agenda: dayMap[key(picked)] || []

    // ----------------------------------------------------------- grid / clock
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property date now: clock.date
    readonly property date first: new Date(now.getFullYear(), now.getMonth() + shift, 1)
    readonly property int year: first.getFullYear()
    readonly property int month: first.getMonth()
    readonly property int lead: (first.getDay() + 6) % 7
    readonly property date gridStart: new Date(year, month, 1 - lead)

    function open() {
        shift = 0;
        picked = new Date();
        adding = false;
        viewing = null;
        ioOpen = false;
        ioStatus = "";
        visible = true;
    }
    function toggle() {
        if (visible) visible = false;
        else open();
    }
    function pick(d) {
        picked = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        if (d.getMonth() !== month || d.getFullYear() !== year)
            shift = (d.getFullYear() - now.getFullYear()) * 12 + d.getMonth() - now.getMonth();
        adding = false;
        viewing = null;
    }
    function goToday() {
        shift = 0;
        pick(new Date());
    }

    // ----------------------------------------------------------- the window
    // where this window sits on the screen, for the hint overlay
    readonly property real hintOx: margins.left
    readonly property real hintOy: margins.top

    screen: target && QsWindow.window ? QsWindow.window.screen : null
    anchors { top: true; left: true }
    margins {
        left: target ? Math.round(BarTargets.origin.x + target.mapToItem(null, 0, 0).x + (target.width - width) / 2) : 0
        top: target ? Math.round(BarTargets.origin.y + target.mapToItem(null, 0, 0).y + target.height + 4) : 0
    }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    // fixed size: the window never resizes when the content changes (a resize made the
    // compositor re-map it); only the card is solid, the rest lets clicks through
    implicitHeight: Math.min(840, (screen ? screen.height : 1000) - margins.top - 8)
    mask: Region { item: card }
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "quickshell-calendar"
    WlrLayershell.layer: WlrLayer.Top   // below the power-fx cursor effect (Overlay)
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // leave both the clock and the card for a moment: close (not while typing)
    Timer {
        id: leave
        interval: 900
        onTriggered: if (!root.adding) root.visible = false
    }
    readonly property bool over: clockHovered || cardHover.hovered
    onOverChanged: if (visible) { if (over) leave.stop(); else leave.restart(); }
    onVisibleChanged: if (visible && !over) leave.restart(); else if (!visible) leave.stop()

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 44
        radius: 22
        color: Theme.alpha(Theme.c("base"), 0.96)
        border { width: 1; color: Theme.alpha(Theme.c("flow-4"), 0.35) }
        focus: true
        Keys.onEscapePressed: { if (root.adding) root.adding = false; else root.visible = false; }

        HoverHandler { id: cardHover }
        WheelHandler {
            onWheel: ev => root.shift += ev.angleDelta.y > 0 ? -1 : 1
        }

        Column {
            id: col
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 14

            // ---- header: < Month Year > ----
            Item {
                width: parent.width
                height: 36

                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: prevMa.containsMouse ? Theme.tint(0.1) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: Theme.c("flow-4")
                        font { family: Theme.font; pixelSize: 20 }
                    }
                    HintArea {
                        id: prevMa
                        popup: root
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.shift--
                        Accessible.role: Accessible.Button
                        Accessible.name: "Previous month"
                        Accessible.onPressAction: root.shift--
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    height: 36
                    width: title.implicitWidth + 32
                    radius: 18
                    color: titleMa.containsMouse ? Theme.tint(0.1) : "transparent"
                    Text {
                        id: title
                        anchors.centerIn: parent
                        text: Qt.formatDate(root.first, "MMMM yyyy")
                        color: Theme.c("lavender")
                        font { family: Theme.font; pixelSize: 17; bold: true }
                    }
                    HintArea {
                        id: titleMa
                        popup: root
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToday()
                        Accessible.role: Accessible.Button
                        Accessible.name: "Back to today"
                        Accessible.onPressAction: root.goToday()
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    width: 36; height: 36; radius: 18
                    color: nextMa.containsMouse ? Theme.tint(0.1) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: Theme.c("flow-4")
                        font { family: Theme.font; pixelSize: 20 }
                    }
                    HintArea {
                        id: nextMa
                        popup: root
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.shift++
                        Accessible.role: Accessible.Button
                        Accessible.name: "Next month"
                        Accessible.onPressAction: root.shift++
                    }
                }
            }

            // ---- weekday names (first column is the week number) ----
            Row {
                width: parent.width
                Repeater {
                    model: ["", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Text {
                        required property string modelData
                        required property int index
                        width: parent.width / 8
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: index >= 6 ? Theme.c("flow-12") : Theme.c("flow-4")
                        opacity: 0.8
                        font { family: Theme.font; pixelSize: 12; bold: true }
                    }
                }
            }

            // ---- 6 weeks x (week number + 7 days) ----
            Grid {
                id: grid
                width: parent.width
                columns: 8
                readonly property real cell: width / 8

                Repeater {
                    model: 48
                    Item {
                        id: cellItem
                        required property int index
                        readonly property int row: Math.floor(index / 8)
                        readonly property int colN: index % 8          // 0 = week number
                        readonly property date d: new Date(root.gridStart.getFullYear(), root.gridStart.getMonth(), root.gridStart.getDate() + row * 7 + (colN - 1))
                        readonly property bool weekCol: colN === 0
                        readonly property bool inMonth: d.getMonth() === root.month
                        readonly property bool today: d.getFullYear() === root.now.getFullYear() && d.getMonth() === root.now.getMonth() && d.getDate() === root.now.getDate()
                        readonly property bool isPicked: !weekCol && root.key(d) === root.key(root.picked)
                        readonly property bool weekend: colN >= 6
                        readonly property int nEvents: weekCol ? 0 : (root.dayMap[root.key(d)] || []).length

                        width: grid.cell
                        height: 44

                        Rectangle {
                            visible: !cellItem.weekCol
                            x: (parent.width - width) / 2
                            y: 2
                            width: 34; height: 34; radius: 17
                            color: cellItem.today ? Theme.c("flow-4")
                                 : dayMa.containsMouse ? Theme.tint(0.1)
                                 : "transparent"
                            border { width: cellItem.isPicked && !cellItem.today ? 1.5 : 0; color: Theme.c("flow-4") }
                        }

                        Text {
                            x: (parent.width - width) / 2
                            y: cellItem.weekCol ? 12 : 11
                            text: cellItem.weekCol ? root.isoWeek(new Date(cellItem.d.getFullYear(), cellItem.d.getMonth(), cellItem.d.getDate() + 3)) : cellItem.d.getDate()
                            font {
                                family: Theme.font
                                pixelSize: cellItem.weekCol ? 11 : 14
                                bold: cellItem.today
                            }
                            color: cellItem.weekCol ? Theme.c("green")
                                 : cellItem.today ? Theme.c("base")
                                 : cellItem.weekend ? Theme.c("flow-12")
                                 : Theme.c("text")
                            opacity: cellItem.weekCol ? 0.55 : cellItem.inMonth ? 1 : 0.28
                        }

                        // one dot per event, up to three
                        Row {
                            visible: cellItem.nEvents > 0
                            x: (parent.width - width) / 2
                            y: 37
                            spacing: 3
                            opacity: cellItem.inMonth ? 1 : 0.35
                            Repeater {
                                model: Math.min(3, cellItem.nEvents)
                                Rectangle {
                                    width: 4; height: 4; radius: 2
                                    color: Theme.c("flow-10")
                                }
                            }
                        }

                        HintArea {
                            id: dayMa
                            popup: root
                            visible: !cellItem.weekCol
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            Accessible.role: Accessible.Button
                            Accessible.name: Qt.formatDate(cellItem.d, "dddd d MMMM yyyy") + (cellItem.today ? ", today" : "") + (cellItem.nEvents ? ", " + cellItem.nEvents + " events" : "")
                            Accessible.onPressAction: root.pick(cellItem.d)
                            onClicked: root.pick(cellItem.d)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.alpha(Theme.c("text"), 0.15)
            }

            // ---- agenda header: picked day + add button ----
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(root.picked, "dddd, d MMMM")
                    color: Theme.c("lavender")
                    font { family: Theme.font; pixelSize: 14; bold: true }
                }

                Rectangle {
                    anchors.right: parent.right
                    width: addLabel.implicitWidth + 24
                    height: 28
                    radius: 14
                    color: root.adding ? Theme.c("flow-4") : addMa.containsMouse ? Theme.tint(0.14) : Theme.tint(0.07)
                    Text {
                        id: addLabel
                        anchors.centerIn: parent
                        text: root.adding ? "Cancel" : "+ Event"
                        color: root.adding ? Theme.c("base") : Theme.c("flow-4")
                        font { family: Theme.font; pixelSize: 12; bold: true }
                    }
                    HintArea {
                        id: addMa
                        popup: root
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.adding ? root.adding = false : form.begin(null)
                        Accessible.role: Accessible.Button
                        Accessible.name: root.adding ? "Cancel new event" : "Add event"
                        Accessible.onPressAction: clicked(null)
                    }
                }
            }

            // ---- events of the picked day ----
            Text {
                visible: root.agenda.length === 0 && !root.adding && !root.viewing
                text: "Nothing planned"
                color: Theme.c("text")
                opacity: 0.45
                font { family: Theme.font; pixelSize: 13 }
            }

            Flickable {
                id: list
                visible: root.agenda.length > 0 && !root.adding && !root.viewing
                width: parent.width
                height: Math.min(contentHeight, 4 * 40)
                contentHeight: rows.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: rows
                    width: list.width
                    spacing: 6

                    Repeater {
                        model: root.agenda
                        Rectangle {
                            id: evRow
                            required property var modelData
                            readonly property var ev: modelData.ev
                            readonly property color accent: Theme.c("flow-" + (1 + Math.abs(String(ev.uid).split("").reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 0)) % 12))
                            width: rows.width
                            height: 34
                            radius: 10
                            color: Theme.tint(rowMa.containsMouse ? 0.09 : 0.05)

                            Rectangle {
                                x: 8; y: 7
                                width: 3; height: 20; radius: 1.5
                                color: evRow.accent
                            }
                            Text {
                                id: timeText
                                x: 19
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                text: evRow.modelData.allDay ? "all day"
                                    : evRow.ev.task || +evRow.modelData.end === +evRow.modelData.start ? Qt.formatTime(evRow.modelData.start, "HH:mm")
                                    : Qt.formatTime(evRow.modelData.start, "HH:mm") + "–" + Qt.formatTime(evRow.modelData.end, "HH:mm")
                                color: Theme.c("flow-4")
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            Text {
                                anchors {
                                    left: timeText.right
                                    right: parent.right
                                    rightMargin: 28
                                    verticalCenter: parent.verticalCenter
                                }
                                text: (evRow.ev.task ? (evRow.ev.done ? "☑ " : "☐ ") : "") + evRow.ev.title + (evRow.ev.location ? "  ·  " + evRow.ev.location : "")
                                elide: Text.ElideRight
                                color: Theme.c("text")
                                opacity: evRow.ev.done ? 0.5 : 1
                                font { family: Theme.font; pixelSize: 13; strikeout: !!evRow.ev.done }
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: "›"
                                color: Theme.c("text")
                                opacity: rowMa.containsMouse ? 0.8 : 0.3
                                font { family: Theme.font; pixelSize: 16 }
                            }
                            HintArea {
                                id: rowMa
                                popup: root
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.viewing = evRow.modelData
                                Accessible.role: Accessible.Button
                                Accessible.name: "Open " + evRow.ev.title
                                Accessible.onPressAction: root.viewing = evRow.modelData
                            }
                        }
                    }
                }
            }

            // ---- details of one event ----
            Column {
                id: details
                visible: !!root.viewing && !root.adding
                width: parent.width
                spacing: 10

                readonly property var occ: root.viewing
                readonly property var ev: occ ? occ.ev : null

                Row {
                    spacing: 10
                    Rectangle {
                        width: 4; height: titleCol.implicitHeight; radius: 2
                        color: details.ev ? Theme.c("flow-" + (1 + Math.abs(String(details.ev.uid).split("").reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 0)) % 12)) : "transparent"
                    }
                    Column {
                        id: titleCol
                        width: details.width - 14
                        spacing: 4
                        Text {
                            width: parent.width
                            text: details.ev ? details.ev.title : ""
                            wrapMode: Text.Wrap
                            color: Theme.c("text")
                            font { family: Theme.font; pixelSize: 17; bold: true }
                        }
                        Text {
                            width: parent.width
                            text: !details.occ ? "" : details.occ.allDay
                                ? Qt.formatDate(details.occ.start, "ddd d MMM") + (root.key(root.addDays(details.occ.end, -1)) !== root.key(details.occ.start) ? " – " + Qt.formatDate(root.addDays(details.occ.end, -1), "ddd d MMM") : "") + "  ·  all day"
                                : details.ev.task || +details.occ.end === +details.occ.start ? Qt.formatDate(details.occ.start, "ddd d MMM") + "  ·  " + Qt.formatTime(details.occ.start, "HH:mm")
                                : Qt.formatDate(details.occ.start, "ddd d MMM") + "  ·  " + Qt.formatTime(details.occ.start, "HH:mm") + " – "
                                  + (root.key(details.occ.end) !== root.key(details.occ.start) ? Qt.formatDate(details.occ.end, "ddd d MMM") + " " : "") + Qt.formatTime(details.occ.end, "HH:mm")
                            wrapMode: Text.Wrap
                            color: Theme.c("flow-4")
                            font { family: Theme.font; pixelSize: 13 }
                        }
                        Text {
                            visible: !!(details.ev && details.ev.task)
                            width: parent.width
                            text: details.ev && details.ev.task ? (details.ev.done ? "☑  Task · done" : "☐  Task · open") + (details.ev.cat ? "  ·  " + details.ev.cat : "") : ""
                            color: Theme.c("text")
                            opacity: 0.75
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Text {
                            visible: !!(details.ev && details.ev.rrule)
                            width: parent.width
                            text: details.ev && details.ev.rrule ? "↻  " + root.describeRule(details.ev.rrule) : ""
                            wrapMode: Text.Wrap
                            color: Theme.c("text")
                            opacity: 0.65
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Text {
                            visible: !!(details.ev && details.ev.location)
                            width: parent.width
                            text: details.ev && details.ev.location ? "⌖  " + details.ev.location : ""
                            wrapMode: Text.Wrap
                            color: Theme.c("text")
                            opacity: 0.75
                            font { family: Theme.font; pixelSize: 13 }
                        }
                    }
                }

                Rectangle {
                    visible: !!(details.ev && details.ev.desc)
                    width: parent.width
                    height: Math.min(notesView.contentHeight, 110) + 20
                    radius: 12
                    color: Theme.tint(0.05)
                    Flickable {
                        id: notesView
                        anchors { fill: parent; margins: 10 }
                        contentHeight: notesText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: notesText
                            width: notesView.width
                            text: details.ev && details.ev.desc ? details.ev.desc : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.c("text")
                            opacity: 0.8
                            font { family: Theme.font; pixelSize: 12 }
                        }
                    }
                }

                Row {
                    spacing: 8
                    height: 34

                    Btn {
                        popup: root
                        label: "‹ Back"
                        onActivated: root.viewing = null
                    }
                    Btn {
                        popup: root
                        visible: !!(details.ev && details.ev.task)
                        label: details.ev && details.ev.done ? "Mark open" : "Mark done"
                        onActivated: {
                            root.replaceEvent(details.ev.uid, details.ev.start, Object.assign({}, details.ev, { done: !details.ev.done }));
                            root.viewing = null;
                        }
                    }
                    Btn {
                        popup: root
                        label: "Edit"
                        primary: true
                        onActivated: form.begin(details.occ)
                    }
                    Btn {
                        popup: root
                        visible: !!(details.ev && details.ev.rrule)
                        label: "Delete this one"
                        danger: true
                        onActivated: {
                            root.skipOccurrence(details.ev.uid, details.ev.start, root.key(details.occ.start));
                            root.viewing = null;
                        }
                    }
                    Btn {
                        popup: root
                        label: details.ev && details.ev.rrule ? "Delete all" : "Delete"
                        danger: true
                        onActivated: {
                            root.removeEvent(details.ev.uid, details.ev.start);
                            root.viewing = null;
                        }
                    }
                }
            }

            // ---- new event / edit form ----
            Column {
                id: form
                visible: root.adding
                width: parent.width
                spacing: 10

                property bool allDay: false
                property bool isTask: false
                property string repeat: "none"
                property var orig: null          // event being edited (null = new)
                property int spanDays: 0         // edit: days between start date and end date, kept
                readonly property bool complex: !!(orig && orig.rrule && !(orig.rrule.interval <= 1 && !orig.rrule.count && !orig.rrule.until && !(orig.rrule.byday && orig.rrule.byday.length)))
                readonly property var repeats: complex ? ["none", "DAILY", "WEEKLY", "MONTHLY", "YEARLY", "keep"] : ["none", "DAILY", "WEEKLY", "MONTHLY", "YEARLY"]

                function localHm(d) { return root.pad(d.getHours()) + ":" + root.pad(d.getMinutes()); }

                // occ: an occurrence from the agenda to edit, or null for a new event on the picked day
                function begin(occ) {
                    orig = occ ? occ.ev : null;
                    root.viewing = null;
                    if (occ) {
                        const ev = occ.ev;
                        const s = root.parseStart(ev);
                        const e = root.parseEnd(ev, s);
                        titleIn.text = ev.title || "";
                        locIn.text = ev.location || "";
                        notesIn.text = ev.desc || "";
                        allDay = !!ev.allDay;
                        isTask = !!ev.task;
                        dateIn.text = root.key(s);
                        startIn.text = allDay ? "09:00" : localHm(s);
                        endIn.text = allDay ? "10:00" : localHm(e);
                        const e2 = allDay ? root.addDays(e, -1) : e;
                        spanDays = Math.max(0, Math.round((new Date(e2.getFullYear(), e2.getMonth(), e2.getDate()) - new Date(s.getFullYear(), s.getMonth(), s.getDate())) / 86400000));
                        const r = ev.rrule;
                        repeat = !r ? "none" : complex ? "keep" : r.freq;
                    } else {
                        titleIn.text = "";
                        locIn.text = "";
                        notesIn.text = "";
                        dateIn.text = root.key(root.picked);
                        startIn.text = "09:00";
                        endIn.text = "10:00";
                        allDay = false;
                        isTask = false;
                        spanDays = 0;
                        repeat = "none";
                    }
                    root.adding = true;
                    titleIn.forceActiveFocus();
                }

                function hm(s) {
                    const m = /^(\d{1,2}):(\d{2})$/.exec(s.trim());
                    if (!m || +m[1] > 23 || +m[2] > 59) return -1;
                    return +m[1] * 60 + +m[2];
                }
                function parseDay(s) {
                    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s.trim());
                    if (!m) return null;
                    const d = new Date(+m[1], +m[2] - 1, +m[3]);
                    return d.getMonth() === +m[2] - 1 ? d : null;
                }

                function submit() {
                    const title = titleIn.text.trim();
                    if (!title) { titleIn.forceActiveFocus(); return; }
                    const d = parseDay(dateIn.text);
                    if (!d) { dateIn.forceActiveFocus(); return; }
                    const ev = { uid: orig ? orig.uid : "qs-" + Date.now(), title: title, exdate: orig && orig.exdate ? orig.exdate : [] };
                    if (locIn.text.trim()) ev.location = locIn.text.trim();
                    if (notesIn.text.trim()) ev.desc = notesIn.text.trim();
                    if (allDay) {
                        ev.allDay = true;
                        ev.start = root.key(d);
                        ev.end = root.key(root.addDays(d, spanDays + 1));
                    } else {
                        const a = hm(startIn.text), b = isTask ? hm(startIn.text) : hm(endIn.text);
                        if (a < 0) { startIn.forceActiveFocus(); return; }
                        if (b < 0) { endIn.forceActiveFocus(); return; }
                        const days = spanDays > 0 ? spanDays : (b <= a ? 1 : 0);
                        const s = new Date(d.getFullYear(), d.getMonth(), d.getDate(), Math.floor(a / 60), a % 60);
                        const e = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, Math.floor(b / 60), b % 60);
                        ev.allDay = false;
                        ev.start = s.toISOString().replace(".000", "");
                        ev.end = e.toISOString().replace(".000", "");
                    }
                    if (isTask) {
                        ev.task = true;
                        ev.done = !!(orig && orig.done);
                        ev.end = ev.start;
                    }
                    if (orig && orig.cat) ev.cat = orig.cat;
                    if (repeat === "keep") ev.rrule = orig.rrule;
                    else if (repeat !== "none") ev.rrule = { freq: repeat, interval: 1 };
                    if (orig) root.replaceEvent(orig.uid, orig.start, ev);
                    else root.addEvent(ev);
                    root.adding = false;
                    root.picked = d;
                    if (d.getMonth() !== root.month || d.getFullYear() !== root.year)
                        root.shift = (d.getFullYear() - root.now.getFullYear()) * 12 + d.getMonth() - root.now.getMonth();
                }

                // title
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 12
                    color: Theme.tint(0.07)
                    border { width: titleIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }

                    TextInput {
                        id: titleIn
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.c("text")
                        clip: true
                        selectByMouse: true
                        font { family: Theme.font; pixelSize: 14 }
                        KeyNavigation.tab: dateIn
                        Keys.onEscapePressed: root.adding = false
                        Keys.onReturnPressed: form.submit()
                        Keys.onEnterPressed: form.submit()
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Event title"

                        Text {
                            visible: !titleIn.text
                            text: "Title"
                            color: Theme.c("text")
                            opacity: 0.4
                            font: titleIn.font
                        }
                    }
                }

                // date + times
                Row {
                    spacing: 8
                    height: 32

                    Rectangle {
                        width: 104; height: 32; radius: 10
                        color: Theme.tint(0.07)
                        border { width: dateIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                        TextInput {
                            id: dateIn
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: form.parseDay(text) ? Theme.c("text") : Theme.c("flow-12")
                            selectByMouse: true
                            font { family: Theme.font; pixelSize: 13 }
                            KeyNavigation.tab: startIn
                            Keys.onEscapePressed: root.adding = false
                            Keys.onReturnPressed: form.submit()
                            Keys.onEnterPressed: form.submit()
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "Date, year-month-day"
                        }
                    }
                    Rectangle {
                        visible: !form.allDay
                        width: 64; height: 32; radius: 10
                        color: Theme.tint(0.07)
                        border { width: startIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                        TextInput {
                            id: startIn
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: form.hm(text) < 0 ? Theme.c("flow-12") : Theme.c("text")
                            selectByMouse: true
                            font { family: Theme.font; pixelSize: 13 }
                            KeyNavigation.tab: endIn
                            Keys.onEscapePressed: root.adding = false
                            Keys.onReturnPressed: form.submit()
                            Keys.onEnterPressed: form.submit()
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "Start time"
                        }
                    }
                    Text {
                        visible: !form.allDay && !form.isTask
                        anchors.verticalCenter: parent.verticalCenter
                        text: "–"
                        color: Theme.c("text")
                        opacity: 0.5
                    }
                    Rectangle {
                        visible: !form.allDay && !form.isTask
                        width: 64; height: 32; radius: 10
                        color: Theme.tint(0.07)
                        border { width: endIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                        TextInput {
                            id: endIn
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: form.hm(text) < 0 ? Theme.c("flow-12") : Theme.c("text")
                            selectByMouse: true
                            font { family: Theme.font; pixelSize: 13 }
                            KeyNavigation.tab: locIn
                            Keys.onEscapePressed: root.adding = false
                            Keys.onReturnPressed: form.submit()
                            Keys.onEnterPressed: form.submit()
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "End time"
                        }
                    }
                }

                // all day + repeat
                Row {
                    spacing: 8
                    height: 32

                    Btn {
                        popup: root
                        height: 32
                        label: "Task"
                        primary: form.isTask
                        onActivated: form.isTask = !form.isTask
                    }
                    Btn {
                        popup: root
                        height: 32
                        label: "All day"
                        primary: form.allDay
                        onActivated: form.allDay = !form.allDay
                    }
                    Btn {
                        popup: root
                        height: 32
                        label: form.repeat === "none" ? "No repeat"
                             : form.repeat === "keep" ? root.describeRule(form.orig.rrule)
                             : "Every " + ({ DAILY: "day", WEEKLY: "week", MONTHLY: "month", YEARLY: "year" })[form.repeat]
                        primary: form.repeat !== "none"
                        onActivated: form.repeat = form.repeats[(form.repeats.indexOf(form.repeat) + 1) % form.repeats.length]
                    }
                }

                Text {
                    visible: !!(form.orig && form.orig.rrule)
                    text: "Editing changes every occurrence of this event."
                    color: Theme.c("text")
                    opacity: 0.5
                    font { family: Theme.font; pixelSize: 11 }
                }

                // location
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 12
                    color: Theme.tint(0.07)
                    border { width: locIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                    TextInput {
                        id: locIn
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.c("text")
                        clip: true
                        selectByMouse: true
                        font { family: Theme.font; pixelSize: 13 }
                        KeyNavigation.tab: notesIn
                        Keys.onEscapePressed: root.adding = false
                        Keys.onReturnPressed: form.submit()
                        Keys.onEnterPressed: form.submit()
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Location"
                        Text {
                            visible: !locIn.text
                            text: "Location"
                            color: Theme.c("text")
                            opacity: 0.4
                            font: locIn.font
                        }
                    }
                }

                // notes (Enter = new line, Ctrl+Enter saves)
                Rectangle {
                    width: parent.width
                    height: 72
                    radius: 12
                    color: Theme.tint(0.07)
                    border { width: notesIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                    TextEdit {
                        id: notesIn
                        anchors { fill: parent; margins: 10 }
                        color: Theme.c("text")
                        wrapMode: TextEdit.Wrap
                        clip: true
                        selectByMouse: true
                        font { family: Theme.font; pixelSize: 13 }
                        KeyNavigation.tab: titleIn
                        KeyNavigation.priority: KeyNavigation.BeforeItem
                        Keys.onEscapePressed: root.adding = false
                        Keys.onPressed: ev => {
                            if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && (ev.modifiers & Qt.ControlModifier)) {
                                form.submit();
                                ev.accepted = true;
                            }
                        }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Notes"
                        Text {
                            visible: !notesIn.text
                            text: "Notes"
                            color: Theme.c("text")
                            opacity: 0.4
                            font: notesIn.font
                        }
                    }
                }

                // save
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 17
                    color: saveMa.containsMouse ? Theme.mix(Theme.c("flow-4"), Theme.ink, 0.15) : Theme.c("flow-4")
                    Text {
                        anchors.centerIn: parent
                        text: form.orig ? "Save changes" : "Save event"
                        color: Theme.c("base")
                        font { family: Theme.font; pixelSize: 13; bold: true }
                    }
                    HintArea {
                        id: saveMa
                        popup: root
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: form.submit()
                        Accessible.role: Accessible.Button
                        Accessible.name: "Save event"
                        Accessible.onPressAction: form.submit()
                    }
                }
            }

            // ---- import / export ----
            Rectangle {
                visible: !root.adding && !root.viewing
                width: parent.width
                height: 1
                color: Theme.alpha(Theme.c("text"), 0.15)
            }
            Row {
                visible: !root.adding && !root.viewing
                spacing: 8
                Btn {
                    popup: root
                    height: 30
                    label: "Import .ics"
                    primary: root.ioOpen
                    onActivated: root.toggleImport()
                }
                Btn {
                    popup: root
                    height: 30
                    label: "Export .ics"
                    onActivated: root.runExport()
                }
            }
            Row {
                visible: root.ioOpen && !root.adding && !root.viewing
                width: parent.width
                spacing: 8
                Rectangle {
                    width: parent.width - goBtn.width - 8
                    height: 32
                    radius: 10
                    color: Theme.tint(0.07)
                    border { width: ioIn.activeFocus ? 1.5 : 0; color: Theme.c("flow-4") }
                    TextInput {
                        id: ioIn
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.c("text")
                        clip: true
                        selectByMouse: true
                        font { family: Theme.font; pixelSize: 12 }
                        Keys.onReturnPressed: root.runImport()
                        Keys.onEnterPressed: root.runImport()
                        Keys.onEscapePressed: root.ioOpen = false
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Path of the .ics file to import"
                        Text {
                            visible: !ioIn.text
                            text: "/path/to/file.ics"
                            color: Theme.c("text")
                            opacity: 0.4
                            font: ioIn.font
                        }
                    }
                }
                Btn {
                    id: goBtn
                    popup: root
                    height: 32
                    label: "Import"
                    primary: true
                    onActivated: root.runImport()
                }
            }
            Text {
                visible: root.ioStatus !== "" && !root.adding && !root.viewing
                width: parent.width
                text: root.ioStatus
                wrapMode: Text.Wrap
                color: Theme.c("text")
                opacity: 0.7
                font { family: Theme.font; pixelSize: 12 }
            }
        }
    }
}
