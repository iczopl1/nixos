import QtQuick
import Quickshell
import Quickshell.Io

// Rotates eDP-1 to match the accelerometer. Port of ~/.config/mango/autorotate.sh
// (two sh processes around monitor-sensor); monitor-sensor is the only thing left
// running, as a child of the bar. Only inside mango, like Mango.qml.
Item {
    id: root

    readonly property var transforms: ({
        "normal": "normal", "bottom-up": "180", "left-up": "90", "right-up": "270"
    })

    Process {
        id: sensor
        running: Mango.active
        command: ["monitor-sensor", "--accel"]
        Component.onDestruction: running = false   // a reload must not leave the child behind
        stdout: SplitParser {
            onRead: line => {
                const m = /orientation changed: (\S+)/.exec(line);
                const t = m ? root.transforms[m[1]] : undefined;
                if (t) Quickshell.execDetached(["wlr-randr", "--output", "eDP-1", "--transform", t]);
            }
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: sensor.running = Mango.active
    }
}
