// Czyta raw key events z jednego urządzenia wejściowego przez evtest.
// Każde key-down zdarzenie zgłasza do WpmBorder.registerKeypress().
import QtQuick
import Quickshell.Io

Item {
    id: reader
    required property string devicePath

    Process {
        id: evtestProc
        // evtest <device> – strumieniuje zdarzenia na stdout
        command: ["evtest", reader.devicePath]
        running: true

        stdout: SplitParser {
            onRead: line => {
                // Linia key-down: "Event: time X, type 1 (EV_KEY), code X (...), value 1"
                // value 2 = autorepeat – nie liczymy (tylko prawdziwe naciśnięcia)
                if (line.includes("type 1") && line.includes("value 1") && !line.includes("value 10"))
                    WpmBorder.registerKeypress()
            }
        }

        // Restart jeśli evtest padnie (np. przy hotplug klawiatury)
        onExited: code => {
            if (code !== 0) Qt.callLater(() => { running = true })
        }
    }
}
