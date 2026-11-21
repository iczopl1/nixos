// Efekt blasku krawędzi ekranu synchronizowany z prędkością pisania (WPM).
// 4 paski gradientu na krawędziach ekranu (WlrLayer.Bottom – pod oknami, nad tapetą).
// Nie blokuje wejścia myszy/klawiatury (Bottom < Normal layer).
// Kolor i jasność zmieniają się płynnie: błękit (wolno) → pomarańcz → czerwień (szybko).
// Wyłącznik: ten sam co obramówka WPM – `effects wpm-color off` (WpmBorder.colorEnabled).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Pragma-Singleton types are only instantiated once something reads a property on
    // them (object-declaration syntax like `TypingGlow {}` is invalid QML for these) –
    // bar/shell.qml reads this to force the singleton (and its PanelWindows) to exist.
    readonly property bool active: true

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: glowWin
            required property var modelData
            screen: modelData
            color: "transparent"

            // Pełny ekran bez zajmowania strefy exkluzywnej
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "qs-typing-glow"

            // --- Animowany stan blasku ---
            property color glowColor:   "#9eeaf9"
            property real  glowOpacity: 0.0
            readonly property int glowWidth: 14   // px – pasuje do gap_outer w mango

            Behavior on glowColor   { ColorAnimation  { duration: 300 } }
            Behavior on glowOpacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // --- Pulsowanie przy każdym naciśnięciu klawisza ---
            SequentialAnimation {
                id: pulseAnim
                // Błysk do max
                NumberAnimation {
                    target: glowWin; property: "glowOpacity"
                    to: glowWin._targetOpacity + 0.25
                    duration: 55; easing.type: Easing.OutQuad
                }
                // Opad do poziomu bazowego WPM
                NumberAnimation {
                    target: glowWin; property: "glowOpacity"
                    to: glowWin._targetOpacity
                    duration: 500; easing.type: Easing.OutCubic
                }
            }

            property real _targetOpacity: 0.0

            Connections {
                target: WpmBorder
                function onKeypressed() {
                    if (!WpmBorder.colorEnabled) return
                    fadeOut.stop()
                    pulseAnim.restart()
                }
            }

            // Wygaszenie po zakończeniu pisania
            NumberAnimation {
                id: fadeOut
                target: glowWin; property: "glowOpacity"
                to: 0.0; duration: 1800; easing.type: Easing.OutCubic
            }

            // --- Aktualizacja koloru i poziomu bazowego (co 300 ms) ---
            Timer {
                interval: 300; running: true; repeat: true
                onTriggered: {
                    var w = WpmBorder.colorEnabled ? WpmBorder.wpm : 0
                    if (w >= 70)      { glowWin.glowColor = "#f7768e"; glowWin._targetOpacity = 0.60 }
                    else if (w >= 45) { glowWin.glowColor = "#ff9e64"; glowWin._targetOpacity = 0.47 }
                    else if (w >= 20) { glowWin.glowColor = "#e0af68"; glowWin._targetOpacity = 0.34 }
                    else if (w >= 5)  { glowWin.glowColor = "#9eeaf9"; glowWin._targetOpacity = 0.20 }
                    else {
                        glowWin._targetOpacity = 0.0
                        if (!pulseAnim.running)
                            fadeOut.restart()
                    }
                }
            }

            // ===== 4 paski gradientu na krawędziach =====

            // Góra: kolor u góry, transparentny ku środkowi
            Rectangle {
                width: parent.width; height: glowWin.glowWidth
                anchors.top: parent.top
                opacity: glowWin.glowOpacity
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: glowWin.glowColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Dół: kolor na dole, transparentny ku środkowi
            Rectangle {
                width: parent.width; height: glowWin.glowWidth
                anchors.bottom: parent.bottom
                opacity: glowWin.glowOpacity
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: glowWin.glowColor }
                }
            }

            // Lewo: kolor z lewej, transparentny ku środkowi
            Rectangle {
                width: glowWin.glowWidth; height: parent.height
                anchors.left: parent.left
                opacity: glowWin.glowOpacity
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: glowWin.glowColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Prawo: kolor z prawej, transparentny ku środkowi
            Rectangle {
                width: glowWin.glowWidth; height: parent.height
                anchors.right: parent.right
                opacity: glowWin.glowOpacity
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: glowWin.glowColor }
                }
            }
        }
    }
}
