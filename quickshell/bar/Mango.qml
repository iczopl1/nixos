pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Mango tags for the bar, from `mmsg watch all-monitors` (one JSON per line).
// Only runs when the bar is started inside mango.
Singleton {
    id: root

    readonly property bool active: (Quickshell.env("MANGO_INSTANCE_SIGNATURE") || "") !== ""
    property var monitors: []
    readonly property var focused: monitors.find(m => m.active) || null
    // key mode of the focused monitor ("default" or a submap such as "clean")
    readonly property string keymode: focused && focused.keymode ? focused.keymode : "default"

    function monitor(name) {
        return monitors.find(m => m.name === name) || null;
    }

    function view(tag, mon) {
        Quickshell.execDetached(["mmsg", "dispatch", "viewcrossmon," + tag + "," + mon]);
    }

    Process {
        id: watch
        running: root.active
        command: ["mmsg", "watch", "all-monitors"]
        Component.onDestruction: running = false   // a reload must not leave the child behind
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.monitors = JSON.parse(line).monitors || [];
                } catch (e) {}
            }
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: watch.running = root.active
    }
}
