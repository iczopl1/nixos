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

    Timer {
        interval: 800; running: true
        onTriggered: { toggleServer.active = false; toggleServer.active = true }
    }

    function nextTheme() {
        var i = themes.indexOf(currentTheme)
        currentTheme = themes[(i + 1) % themes.length]
        saveState.start()
    }

    Process {
        id: saveState
        function start() {
            command = ["bash", "-c", "echo " + root.currentTheme + " > " + root.stateFile]
            running = false; running = true
        }
    }

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
            exclusionMode: ExclusionMode.Ignore
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
