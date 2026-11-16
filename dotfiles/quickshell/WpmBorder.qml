// T3.13: Kolor i grubość obramówki aktywnego okna zmieniają się z prędkością pisania.
// Monitoruje WSZYSTKIE klawiatury systemowo przez evtest (wymaga grupy input).
// Nie loguje treści klawiszy – liczy tylko zdarzenia key-down.
//
// Naprawione w stosunku do v1:
//  - Stałe okno 10 s (nie span między pierwszym a ostatnim stempelkiem) → brak "1 klawisz = 100 WPM"
//  - Wygładzanie wykładnicze (EMA α=0.3) → płynne przejścia między prędkościami
//  - border_px 2→3→4 (nie 2→6), progi 15/35/60 wpm
//  - Kompensacja gap_inner: wzrost border o X zmniejsza gap o 2X → okna nie skaczą
//  - Puls na każde naciśnięcie: chwilowe +1 do border (120 ms) bez korekty gap
//    → mikroskopijne przesunięcie okna = efekt ruchu (animowane przez mango)
//
// Eksponuje: wpm (int), keypressed (signal) – używane przez TypingGlow i shell.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Stan publiczny ---
    property int    wpm:          0
    signal          keypressed()

    // --- Stan wewnętrzny ---
    property var    _timestamps:  []
    property string _color:       "0x9eeaf9ff"
    property int    _borderPx:    2       // aktualny poziom bazowy (bez pulsu)
    property real   _smoothed:    0.0    // EMA WPM
    property bool   _pulsing:     false  // puls już aktywny → nie nakładaj kolejnego
    // Rozdzielone: kolor obramówki i "ruszanie się" okna (border_px/gap + puls) to dwa
    // osobne efekty (effects-ctl.sh) – można wyłączyć jeden bez drugiego.
    property bool   colorEnabled: true
    property bool   moveEnabled:  true
    // Master switch: zatrzymuje same procesy evtest (EvtestReader.qml) – realny koszt CPU,
    // nie tylko efekt wizualny. colorEnabled/moveEnabled bez tego nadal liczyłyby WPM w tle.
    property bool   countingEnabled: true

    readonly property int    baseGap:    7   // gap_inner default (config.conf)
    readonly property int    baseBorder: 2   // border_px default (config.conf)
    readonly property string defaultColor: "0x9eeaf9ff"

    // --- Trwały zapis stanu togglów (jak particle-effect) – bez tego colorEnabled/
    // moveEnabled/countingEnabled resetowały się do "true" przy każdym restarcie QS,
    // mimo ustawień zmienionych przez `effects wpm-color/wpm-move/wpm-count`. ---
    readonly property string stateFile: Quickshell.env("HOME") + "/.config/wpm-effects"

    Process {
        command: ["bash", "-c", "cat " + root.stateFile + " 2>/dev/null || true"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                var m = line.trim().match(/^(color|move|count)=([01])$/)
                if (!m) return
                var val = m[2] === "1"
                if (m[1] === "color") root.colorEnabled = val
                else if (m[1] === "move") root.moveEnabled = val
                else if (m[1] === "count") root.countingEnabled = val
            }
        }
    }

    Process { id: saveEffectsProc }
    function saveEffectsState() {
        var c = root.colorEnabled ? 1 : 0
        var m = root.moveEnabled ? 1 : 0
        var n = root.countingEnabled ? 1 : 0
        saveEffectsProc.command = ["bash", "-c",
            "printf 'color=%s\\nmove=%s\\ncount=%s\\n' " + c + " " + m + " " + n + " > " + root.stateFile]
        saveEffectsProc.running = false
        saveEffectsProc.running = true
    }
    onColorEnabledChanged: saveEffectsState()
    onMoveEnabledChanged: saveEffectsState()
    onCountingEnabledChanged: saveEffectsState()

    // --- Toggle on/off (effects-ctl.sh) ---
    SocketServer {
        id: colorToggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-wpm-color-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.colorEnabled = !root.colorEnabled }
    }

    SocketServer {
        id: moveToggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-wpm-move-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.moveEnabled = !root.moveEnabled }
    }

    SocketServer {
        id: countToggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-wpm-count-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.countingEnabled = !root.countingEnabled }
    }

    Timer {
        interval: 800; running: true
        onTriggered: {
            countToggleServer.active = false; countToggleServer.active = true
            colorToggleServer.active = false; colorToggleServer.active = true
            moveToggleServer.active = false; moveToggleServer.active = true
        }
    }

    // --- Kolory progowe (format mango 0xRRGGBBAA) ---
    // Progi: 15 / 35 / 60 wpm (łagodniejsze niż poprzednie 5/20/45/70)
    function colorForWpm(w) {
        if (w >= 60)      return "0xf7768eff"   // czerwień
        else if (w >= 35) return "0xff9e64ff"   // pomarańcz
        else if (w >= 15) return "0xe0af68ff"   // bursztyn
        else              return "0x9eeaf9ff"   // błękit
    }

    // border 2→3→4 (zakres zmniejszony, żeby kompensacja gap miała sens)
    function borderPxForWpm(w) {
        if (w >= 60) return 4
        if (w >= 15) return 3
        return 2
    }

    // gap_inner = baseGap - 2*(border - baseBorder)
    // Każdy px wzrostu border = 2px redukcji gap → łączna "ramka okna" stała
    function gapForBorder(px) {
        return Math.max(1, baseGap - 2 * (px - baseBorder))
    }

    // --- Oblicz WPM: stałe okno 10 s, minimum 4 naciśnięcia ---
    // Stały mianownik (10 s) zapobiega gigantycznym wartościom przy szybkich,
    // krótkich burstach (np. 2 klawisze w 0.1 s nie dają 240 WPM).
    function calcWpm() {
        var now    = Date.now() / 1000.0
        var window = 10.0
        var cutoff = now - window
        _timestamps = _timestamps.filter(t => t > cutoff)
        if (_timestamps.length < 4) return 0
        return Math.floor((_timestamps.length / 5.0) / (window / 60.0))
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

    // Rejestracja naciśnięcia + puls
    function registerKeypress() {
        _timestamps.push(Date.now() / 1000.0)
        keypressed()

        // Puls: chwilowe +1 do border_px (120 ms), bez korekty gap
        // → animacja mango przesunie okna o ~1 px i wróci → efekt ruchu
        if (root.moveEnabled && !_pulsing) {
            _pulsing = true
            mmsgPulseOn.start()
            pulseTimer.restart()
        }
    }

    // --- Timer 300 ms: EMA + kolor + border + gap ---
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            var raw = root.countingEnabled ? root.calcWpm() : 0
            // EMA α=0.3: wolno się podnosi i wolno opada → płynne kolory i grubości
            // (gdy wyłączone liczenie: zeruj natychmiast, nie czekaj na wygaszenie EMA)
            root._smoothed = root.countingEnabled ? (0.7 * root._smoothed + 0.3 * raw) : 0
            var w = Math.floor(root._smoothed)
            root.wpm = w

            // Kolor obramówki – osobny toggle
            var color = root.colorEnabled ? root.colorForWpm(w) : root.defaultColor
            if (color !== root._color) {
                root._color = color
                mmsgColor.start()
            }

            // Grubość border + gap (= "ruszanie się" okna) – osobny toggle
            var px = root.moveEnabled ? root.borderPxForWpm(w) : root.baseBorder
            if (px !== root._borderPx) {
                root._borderPx = px
                if (!root._pulsing) mmsgBorder.start()   // nie nadpisuj pulsu
                mmsgGapH.start()
                mmsgGapV.start()
            }
        }
    }

    // Puls: po 120 ms wróć do poziomu bazowego
    Timer {
        id: pulseTimer
        interval: 120; repeat: false
        onTriggered: { root._pulsing = false; mmsgBorder.start() }
    }

    Process {
        id: mmsgColor
        function start() {
            running = false
            command = ["mmsg", "dispatch", "setoption,focus_color," + root._color]
            running = true
        }
    }

    // border_px do poziomu bazowego (lub po pulsie)
    Process {
        id: mmsgBorder
        function start() {
            running = false
            command = ["mmsg", "dispatch", "setoption,border_px," + root._borderPx]
            running = true
        }
    }

    // puls: border_px + 1 (bez korekty gap → mikroskopijny ruch okien)
    Process {
        id: mmsgPulseOn
        function start() {
            running = false
            command = ["mmsg", "dispatch", "setoption,border_px," + (root._borderPx + 1)]
            running = true
        }
    }

    // gap_inner_horizontal skalowany odwrotnie do border
    Process {
        id: mmsgGapH
        function start() {
            running = false
            command = ["mmsg", "dispatch",
                "setoption,gap_inner_horizontal," + root.gapForBorder(root._borderPx)]
            running = true
        }
    }

    // gap_inner_vertical – osobna opcja w mango
    Process {
        id: mmsgGapV
        function start() {
            running = false
            command = ["mmsg", "dispatch",
                "setoption,gap_inner_vertical," + root.gapForBorder(root._borderPx)]
            running = true
        }
    }
}
