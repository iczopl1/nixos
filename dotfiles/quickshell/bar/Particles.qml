// T3.14: Efekty cząsteczkowe na tle ekranu (Quickshell QML).
// Więcej niż jeden motyw może być aktywny naraz (na życzenie użytkownika, 2026-11-19) –
// `activeThemes` to zbiór (array), nie jeden string. Sterowanie: `effects particles-<motyw>
// on|off` (effects-ctl.sh, każdy motyw niezależny przełącznik) albo socket `qs-particles-set`
// (payload: lista motywów oddzielona przecinkami, np. "leaves,snow", albo "" dla braku).
// Plik stanu: ~/.config/particle-effect (lista motywów oddzielona przecinkami, albo puste).
// Warstwa Background pod oknami (Overlay, gdy "cursor" jest aktywny), max 80 cząsteczek
// SUMA po wszystkich aktywnych motywach (nie 80 każdy – MASTER §11), domyślnie wyłączone.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/particle-effect"
    readonly property var particleThemes: ["leaves", "rain", "snow", "sparks", "cursor"]
    readonly property var themeLabels: ({
        leaves: "liście", rain: "deszcz", snow: "śnieg", sparks: "iskry",
        cursor: "piksele za kursorem"
    })
    // Zbiór aktywnych motywów naraz (może być więcej niż jeden, może być pusty = wyłączone).
    property var activeThemes: []
    property bool active: activeThemes.length > 0

    // --- Pozycja kursora (motyw "cursor") – mmsg nie ma "watch cursorpos", więc polling ---
    property real cursorX: 0
    property real cursorY: 0
    property string cursorMonitor: ""

    Timer {
        interval: 80  // ~12.5 Hz – wystarczy dla efektu, nie zasypuje CPU procesami co klatkę
        running: root.activeThemes.indexOf("cursor") >= 0
        repeat: true
        onTriggered: { cursorPoll.running = false; cursorPoll.running = true }
    }

    Process {
        id: cursorPoll
        command: ["mmsg", "get", "cursorpos"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var d = JSON.parse(line)
                    root.cursorX = d.x
                    root.cursorY = d.y
                    root.cursorMonitor = d.monitor
                } catch (e) {}
            }
        }
    }

    function parseThemeList(text) {
        return text.split(",").map(s => s.trim()).filter(s => root.particleThemes.indexOf(s) >= 0)
    }

    // --- Wczytaj zbiór motywów ze stanu przy starcie (lista po przecinku; stary format
    // z jednym motywem albo "off" nadal się czyta poprawnie – split(",") daje 1-elementową
    // listę, a "off"/"" po filtrze zmienia się w pustą listę). ---
    Process {
        command: ["bash", "-c", "cat " + root.stateFile + " 2>/dev/null || true"]
        running: true
        stdout: SplitParser {
            onRead: line => { root.activeThemes = root.parseThemeList(line) }
        }
    }

    // --- Cykl przez socket (qs-particles) – bez przypisanego klawisza na 2026-11-19 (SUPER+F6
    // teraz otwiera `effects` w terminalu), ale socket zostaje gotowy, gdyby kiedyś się przydał:
    // dodaje po kolei kolejny jeszcze nieaktywny motyw; gdy wszystkie są aktywne, czyści wszystkie. ---
    SocketServer {
        id: toggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-particles-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.nextTheme() }
    }

    // --- Ustawienie zbioru motywów (effects-ctl.sh) – payload = lista po przecinku, albo "off"/"" ---
    SocketServer {
        id: setServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-particles-set-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            parser: SplitParser {
                onRead: line => {
                    root.activeThemes = root.parseThemeList(line)
                    saveState.start()
                    root.notifyTheme()
                }
            }
        }
    }

    Timer {
        interval: 800; running: true
        onTriggered: {
            toggleServer.active = false; toggleServer.active = true
            setServer.active = false; setServer.active = true
        }
    }

    function nextTheme() {
        var next = particleThemes.find(t => activeThemes.indexOf(t) < 0)
        activeThemes = next ? activeThemes.concat([next]) : []
        saveState.start()
        notifyTheme()
    }

    Process {
        id: saveState
        function start() {
            command = ["bash", "-c", "echo " + root.activeThemes.join(",") + " > " + root.stateFile]
            running = false; running = true
        }
    }

    // Powiadomienie (mako) po każdej zmianie zbioru motywów (socket qs-particles-set / qs-particles)
    function notifyTheme() {
        var label = activeThemes.length === 0 ? "wyłączone"
            : activeThemes.map(t => themeLabels[t] || t).join(", ")
        notifyProc.command = ["notify-send", "Cząsteczki", label, "-t", "1500"]
        notifyProc.running = false
        notifyProc.running = true
    }

    Process { id: notifyProc }

    // --- Okna cząsteczkowe – jedno per ekran ---
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusiveZone: -1
            // "background" jest zajęte przez cava-bg i awww-daemon (tapeta) – particles tam
            // były zasłaniane, niezależnie od motywu (mmsg get all-layers). "bottom" to warstwa
            // zawsze NAD "background" (gwarancja protokołu, nie zależy od kolejności mapowania).
            // "cursor" (na żądanie), jeśli jest w aktywnym zbiorze, zawsze na overlay – nad
            // wszystkimi oknami (nawet gdy inne motywy w tym samym zbiorze są pod oknami, ta
            // jedna warstwa okna jest wspólna dla całego Canvas – cursor decyduje o warstwie).
            WlrLayershell.layer: root.activeThemes.indexOf("cursor") >= 0 ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.namespace: "qs-particles"

            ParticleCanvas {
                anchors.fill: parent
                themes: root.activeThemes
                running: root.active
                cursorActive: root.cursorMonitor === win.modelData.name
                cursorX: root.cursorX
                cursorY: root.cursorY
            }
        }
    }
}
