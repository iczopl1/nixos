pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One `nmcli monitor` for the whole bar. `changed` fires once per burst of
// NetworkManager events; the network chip re-checks on it (net-state.sh --once).
Singleton {
    id: root

    signal changed

    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        Component.onDestruction: running = false   // a reload must not leave the child behind
        stdout: SplitParser {
            onRead: line => settle.restart()
        }
        onExited: retry.start()
    }

    Timer {
        id: settle
        interval: 1000   // a connect is several lines: let the burst end
        onTriggered: root.changed()
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: {
            monitor.running = true;
            root.changed();
        }
    }
}
