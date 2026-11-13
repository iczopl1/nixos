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
    property bool   enabled:      true

    readonly property int    baseGap:    7   // gap_inner default (config.conf)
    readonly property int    baseBorder: 2   // border_px default (config.conf)
    readonly property string defaultColor: "0x9eeaf9ff"

    // --- Toggle on/off (effects-ctl.sh) ---
    SocketServer {
        id: wpmToggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-wpm-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.enabled = !root.enabled }
    }

    Timer {
        interval: 800; running: true
        onTriggered: { wpmToggleServer.active = false; wpmToggleServer.active = true }
    }

    // --- Kolory progowe (format mango 0xRRGGBBAA) ---
    // Progi: 15 / 35 / 60 wpm (łagodniejsze niż poprzednie 5/20/45/70)
    function colorForWpm(w) {
        if (!enabled)     return defaultColor
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
        if (!_pulsing) {
            _pulsing = true
            mmsgPulseOn.start()
            pulseTimer.restart()
        }
    }

    // --- Timer 300 ms: EMA + kolor + border + gap ---
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (!root.enabled) {
                // Wyłączone (effects-ctl.sh) – wróć do stanu bazowego raz, potem nic nie rób
                if (root._borderPx !== root.baseBorder || root._color !== root.defaultColor) {
                    root._smoothed = 0
                    root.wpm = 0
                    root._color = root.defaultColor
                    mmsgColor.start()
                    root._borderPx = root.baseBorder
                    if (!root._pulsing) mmsgBorder.start()
                    mmsgGapH.start()
                    mmsgGapV.start()
                }
                return
            }
            var raw = root.calcWpm()
            // EMA α=0.3: wolno się podnosi i wolno opada → płynne kolory i grubości
            root._smoothed = 0.7 * root._smoothed + 0.3 * raw
            var w = Math.floor(root._smoothed)
            root.wpm = w

            var color = root.colorForWpm(w)
            if (color !== root._color) {
                root._color = color
                mmsgColor.start()
            }

            var px = root.borderPxForWpm(w)
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
