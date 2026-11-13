// T3.14: Efekty cząsteczkowe na tle ekranu (Quickshell QML).
// SUPER+F6 przełącza motyw: off → leaves → rain → snow → sparks → off
// Plik stanu: ~/.config/particle-effect (nazwa motywu lub "off")
// Warstwa Background pod oknami, max 80 cząsteczek, domyślnie wyłączone (MASTER §11).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/particle-effect"
    readonly property var themes: ["off", "leaves", "rain", "snow", "sparks"]
    readonly property var themeLabels: ({
        off: "wyłączone", leaves: "liście", rain: "deszcz", snow: "śnieg", sparks: "iskry"
    })
    property string currentTheme: "off"
    property bool active: currentTheme !== "off"

    // --- Wczytaj motyw ze stanu przy starcie ---
    Process {
        command: ["bash", "-c", "cat " + root.stateFile + " 2>/dev/null || echo off"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                if (root.themes.indexOf(t) >= 0) root.currentTheme = t
            }
        }
    }

    // --- Toggle przez socket (SUPER+F6) ---
    SocketServer {
        id: toggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-particles-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.nextTheme() }
    }

    // --- Ustawienie konkretnego motywu (effects-ctl.sh) – payload = nazwa motywu ---
    SocketServer {
        id: setServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-particles-set-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            parser: SplitParser {
                onRead: line => {
                    var t = line.trim()
                    if (root.themes.indexOf(t) >= 0) {
                        root.currentTheme = t
                        saveState.start()
                        root.notifyTheme()
                    }
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
        var i = themes.indexOf(currentTheme)
        currentTheme = themes[(i + 1) % themes.length]
        saveState.start()
        notifyTheme()
    }

    Process {
        id: saveState
        function start() {
            command = ["bash", "-c", "echo " + root.currentTheme + " > " + root.stateFile]
            running = false; running = true
        }
    }

    // Powiadomienie (mako) po każdej zmianie motywu – SUPER+F6 i `effects particles <nazwa>`
    function notifyTheme() {
        var label = themeLabels[currentTheme] || currentTheme
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
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qs-particles"

            ParticleCanvas {
                anchors.fill: parent
                theme: root.currentTheme
                running: root.active
            }
        }
    }
}
