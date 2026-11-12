// T3.13: Kolor obramówki aktywnego okna zmienia się z prędkością pisania (WPM).
// Monitoruje WSZYSTKIE klawiaturę systemowo przez evtest (wymaga grupy input).
// Nie loguje treści klawiszy – liczy tylko zdarzenia key-down.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Stan WPM ---
    property var _timestamps: []
    property int  _wpm: 0
    property string _color: "0x9eeaf9ff"
    property bool enabled: true  // można wyłączyć z toggle-effects.sh

    readonly property string defaultColor: "0x9eeaf9ff"  // błękit – zgadza się z config.conf

    // --- Progi kolorów (format mango 0xRRGGBBAA) ---
    function colorForWpm(wpm) {
        if (!enabled)      return defaultColor
        if (wpm >= 70)     return "0xf7768eff"   // czerwień
        else if (wpm >= 45) return "0xff9e64ff"  // pomarańcz
        else if (wpm >= 20) return "0xe0af68ff"  // bursztyn
        else                return "0x9eeaf9ff"  // błękit
    }

    // --- Oblicz WPM z rolling-window 5 s ---
    function calcWpm() {
        var now = Date.now() / 1000.0
        var cutoff = now - 5.0
        _timestamps = _timestamps.filter(t => t > cutoff)
        if (_timestamps.length < 2) return 0
        var elapsed = now - _timestamps[0]
        if (elapsed < 0.1) return 0
        return Math.floor((_timestamps.length / 5.0) / (elapsed / 60.0))
    }

    // --- Znajdź urządzenia klawiatury (wszystkie *-event-kbd z by-path) ---
    Process {
        id: findKbd
        command: ["bash", "-c",
            "ls /dev/input/by-path/*-event-kbd 2>/dev/null | sort -u"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "") {
                    kbdSpawner.addDevice(line.trim())
                }
            }
        }
        onExited: {
            // jeśli nie znaleziono przez by-path, spróbuj platform kbd (trackpad laptopa)
            if (kbdSpawner.deviceCount === 0) {
                kbdSpawner.addDevice("/dev/input/by-path/platform-i8042-serio-0-event-kbd")
            }
        }
    }

    // --- Spawner procesów evtest: jeden per klawiatura ---
    QtObject {
        id: kbdSpawner
        property int deviceCount: 0
        property var procs: []

        function addDevice(path) {
            deviceCount++
            var comp = Qt.createComponent("EvtestReader.qml")
            if (comp.status === Component.Ready) {
                var obj = comp.createObject(root, { devicePath: path })
                procs.push(obj)
            }
        }
    }

    // Publiczne: zarejestruj naciśnięcie klawisza (wywołuje EvtestReader)
    function registerKeypress() {
        _timestamps.push(Date.now() / 1000.0)
    }

    // --- Timer: co 300 ms przelicz WPM i zaktualizuj mmsg ---
    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            var wpm = root.calcWpm()
            var color = root.colorForWpm(wpm)
            if (color !== root._color) {
                root._color = color
                mmsgBorder.start()
            }
        }
    }

    // --- Wywołanie mmsg ---
    Process {
        id: mmsgBorder
        property string pendingColor: ""
        function start() {
            pendingColor = root._color
            running = false
            command = ["mmsg", "dispatch", "setoption,focus_color," + pendingColor]
            running = true
        }
    }
}
