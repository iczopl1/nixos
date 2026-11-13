// T3.13: Kolor i grubość obramówki aktywnego okna zmieniają się z prędkością pisania.
// Monitoruje WSZYSTKIE klawiatury systemowo przez evtest (wymaga grupy input).
// Nie loguje treści klawiszy – liczy tylko zdarzenia key-down.
// Eksponuje: wpm (int), keypressed (signal) – używane przez TypingGlow i shell.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Stan WPM (publiczny) ---
    property int    wpm:     0       // aktualny WPM – do odczytu przez inne QML
    signal          keypressed()     // emitowany przy każdym naciśnięciu klawisza

    // --- Stan wewnętrzny ---
    property var    _timestamps: []
    property string _color:     "0x9eeaf9ff"
    property int    _borderPx:  2
    property bool   enabled:    true

    readonly property string defaultColor: "0x9eeaf9ff"

    // --- Progi kolorów (format mango 0xRRGGBBAA) ---
    function colorForWpm(w) {
        if (!enabled)      return defaultColor
        if (w >= 70)       return "0xf7768eff"   // czerwień
        else if (w >= 45)  return "0xff9e64ff"   // pomarańcz
        else if (w >= 20)  return "0xe0af68ff"   // bursztyn
        else               return "0x9eeaf9ff"   // błękit
    }

    // grubość obramówki: 2px spoczynek → 6px szybko
    function borderPxForWpm(w) {
        if (w >= 70) return 6
        if (w >= 45) return 5
        if (w >= 20) return 4
        if (w >= 5)  return 3
        return 2
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
                if (line.trim() !== "")
                    kbdSpawner.addDevice(line.trim())
            }
        }
        onExited: {
            if (kbdSpawner.deviceCount === 0)
                kbdSpawner.addDevice("/dev/input/by-path/platform-i8042-serio-0-event-kbd")
        }
    }

    QtObject {
        id: kbdSpawner
        property int deviceCount: 0
        property var procs: []
        function addDevice(path) {
            deviceCount++
            var comp = Qt.createComponent("EvtestReader.qml")
            if (comp.status === Component.Ready)
                procs.push(comp.createObject(root, { devicePath: path }))
        }
    }

    // Rejestracja naciśnięcia (wywołuje EvtestReader) + sygnał dla TypingGlow
    function registerKeypress() {
        _timestamps.push(Date.now() / 1000.0)
        keypressed()
    }

    // --- Timer: co 300 ms przelicz WPM, zaktualizuj kolor i grubość ---
    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            var w = root.calcWpm()
            root.wpm = w

            var color = root.colorForWpm(w)
            if (color !== root._color) {
                root._color = color
                mmsgColor.start()
            }

            var px = root.borderPxForWpm(w)
            if (px !== root._borderPx) {
                root._borderPx = px
                mmsgWidth.start()
            }
        }
    }

    Process {
        id: mmsgColor
        function start() {
            running = false
            command = ["mmsg", "dispatch", "setoption,focus_color," + root._color]
            running = true
        }
    }

    Process {
        id: mmsgWidth
        function start() {
            running = false
            command = ["mmsg", "dispatch", "setoption,border_px," + root._borderPx]
            running = true
        }
    }
}
