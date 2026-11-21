import QtQuick
import Quickshell
import Quickshell.Io
import "Markup.js" as Markup

// A waybar "custom/*" module: runs `exec`, reads JSON (or plain) lines, and
// exposes text/tooltip/class. interval > 0 re-runs it; otherwise it streams
// and is restarted if it dies.
Seg {
    id: root

    property string exec: ""
    property int interval: 0
    property string onLeft: ""
    property string onRight: ""
    property string onScroll: ""
    property bool refreshAfterClick: false
    property string raw: ""
    property string rawTip: ""
    property var classes: []

    function hasClass(c) {
        return classes.indexOf(c) >= 0;
    }

    function run(cmd) {
        if (cmd === "") return;
        if (refreshAfterClick) {
            clicker.command = ["setsid", "-w", "sh", "-c", cmd];
            clicker.running = true;
        } else {
            Quickshell.execDetached(["setsid", "sh", "-c", cmd]);
        }
    }

    text: Markup.toHtml(raw)
    tip: Markup.toHtml(rawTip)
    shown: raw !== ""

    onClicked: b => run(b === Qt.LeftButton ? onLeft : b === Qt.RightButton ? onRight : "")
    onScrolled: up => run(onScroll)

    Process {
        id: proc
        // own process group, like waybar: the scripts end with `kill 0`
        command: ["setsid", "-w", "sh", "-c", root.exec]
        running: root.exec !== ""
        stdout: SplitParser {
            onRead: line => {
                if (line.length === 0) return;
                try {
                    const j = JSON.parse(line);
                    root.raw = j.text !== undefined ? String(j.text) : "";
                    root.rawTip = j.tooltip !== undefined ? String(j.tooltip) : "";
                    const c = j["class"];
                    root.classes = c === undefined ? [] : (Array.isArray(c) ? c : [c]);
                } catch (e) {
                    root.raw = line;
                    root.rawTip = "";
                    root.classes = [];
                }
            }
        }
        onExited: if (root.interval <= 0) restart.start()
    }

    Process {
        id: clicker
        onExited: if (root.interval > 0) proc.running = true
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: proc.running = true
    }

    Timer {
        interval: root.interval * 1000
        running: root.interval > 0
        repeat: true
        onTriggered: proc.running = true
    }
}
