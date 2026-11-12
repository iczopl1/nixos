// SUPER+H: overlay z dokumentacją skrótów klawiszowych.
// Toggle przez socket: socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-shortcuts-$WAYLAND_DISPLAY.sock
// Zamknij: Escape, H, spacja lub kliknięcie.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR")

    property bool active: false

    function toggle() { active = !active }
    function close()  { active = false   }

    SocketServer {
        id: toggleServer
        active: true
        path: root.runDir + "/qs-shortcuts-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.toggle() }
    }

    // Rebind po live-reload (jak w Hints.qml)
    Timer {
        interval: 800; running: true
        onTriggered: { toggleServer.active = false; toggleServer.active = true }
    }

    // Dane skrótów: [ { header, items: [ [lewa, prawa] ] } ]
    readonly property var sections: [
        {
            header: "Mango WM",
            items: [
                ["Super + 1–9",         "przejdź do workspace"],
                ["Super + Shift + 1–9", "przenieś okno na workspace"],
                ["Super + H",           "ten overlay (skróty)"],
                ["Super + D",           "Vimium hints (kliknij bez myszy)"],
                ["Super + Tab",         "przełącz okno (rofi)"],
                ["Super + Enter",       "terminal (alacritty)"],
                ["Super + E",           "menedżer plików (Thunar)"],
                ["Super + Space",       "launcher (rofi)"],
                ["Super + Q",           "zamknij okno"],
                ["Super + F",           "pełny ekran"],
                ["Super + V",           "historia schowka (cliphist)"],
                ["Super + F8",          "toggle efekty graficzne"],
                ["Super + F9",          "wyłącz ekran"],
            ]
        },
        {
            header: "nvim – Pliki i okna",
            items: [
                ["Ctrl + N",   "drzewo plików on/off"],
                ["Leader + E", "przejdź do drzewa plików"],
                ["-",          "Oil: edytuj katalog jako bufor"],
                ["Leader + FF","Telescope: szukaj pliku"],
                ["Leader + FW","Telescope: szukaj tekstu"],
                ["Leader + FB","Telescope: lista buforów"],
                ["Leader + FO","Telescope: ostatnie pliki"],
                ["Leader + GG","LazyGit w oknie float"],
                ["Leader + Z", "zen-mode (tryb skupienia)"],
                ["Tab / S-Tab","następny/poprzedni bufor"],
                ["Alt + 1–9",  "skocz do buforu N"],
                ["Leader + X", "zamknij bufor"],
            ]
        },
        {
            header: "nvim – Nawigacja i edycja",
            items: [
                ["s / S",          "flash: skocz do miejsca na ekranie"],
                ["Leader + XX",    "Trouble: panel błędów LSP"],
                ["Leader + FT",    "TODO-komentarze (Telescope)"],
                ["] t / [ t",      "następny/poprzedni TODO"],
                ["Leader + GB",    "git blame: toggle"],
                ["Leader + FM",    "formatuj plik/zaznaczenie"],
                ["cs / ys / ds",   "nvim-surround: zmień/dodaj/usuń otoczenie"],
                ["gS / gJ",        "split/join argumentów (mini.splitjoin)"],
                ["Leader + /",     "komentarz linii/zaznaczenia"],
                ["Alt + H/V/I",    "terminal: poziomy/pionowy/pływający"],
                ["Leader + WK",    "which-key: wszystkie skróty"],
            ]
        },
        {
            header: "Shell",
            items: [
                ["e [plik]",    "edytuj plik (nvim lub fzf picker)"],
                ["a [wzorzec]", "szukaj tekstu (rg+fzf) → nvim"],
                ["q",           "claude (lub picker projektu z ~)"],
                ["qs",          "restart paska Quickshell"],
                ["s",           "git status -sb"],
                ["gl / gp",     "git pull / push"],
                ["w",           "wybierz sieć Wi-Fi (fzf)"],
                ["d",           "historia poleceń (fzf) → wykonaj"],
                ["x / u",       "wejdź do podfolderu / nadrzędnego (fzf)"],
                ["br <wartość>","jasność ekranu (brightnessctl)"],
                ["effects",     "toggle efekty graficzne"],
                ["agent",       "pokaż stan systemu i narzędzi"],
            ]
        }
    ]

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "qs-shortcuts"

            // tło-blur i panel tylko gdy active
            Rectangle {
                anchors.fill: parent
                color: "#aa000000"
                visible: root.active

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                anchors.fill: parent
                visible: root.active
                focus: root.active
                onFocusChanged: if (focus) forceActiveFocus()
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape || e.key === Qt.Key_H || e.key === Qt.Key_Space) {
                        root.close()
                        e.accepted = true
                    }
                }

                // Panel wyśrodkowany
                Rectangle {
                    id: panel
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 920)
                    height: Math.min(parent.height - 60, contentCol.implicitHeight + 40)
                    color: "#1a1b26"
                    radius: 10
                    border.color: "#3b4261"
                    border.width: 1

                    // Scroll gdy nie mieści się wszystko
                    Flickable {
                        anchors { fill: parent; margins: 20 }
                        contentHeight: contentCol.implicitHeight
                        clip: true

                        Column {
                            id: contentCol
                            width: parent.width
                            spacing: 16

                            // Nagłówek
                            Text {
                                width: parent.width
                                text: "Skróty klawiszowe"
                                color: "#7aa2f7"
                                font.pixelSize: 18
                                font.family: "JetBrains Mono"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                text: "Esc / H / kliknięcie – zamknij"
                                color: "#565f89"
                                font.pixelSize: 11
                                font.family: "JetBrains Mono"
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Sekcje w dwóch kolumnach
                            Grid {
                                width: parent.width
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 16

                                Repeater {
                                    model: root.sections

                                    Column {
                                        width: (contentCol.width - 16) / 2
                                        spacing: 4

                                        // Nagłówek sekcji
                                        Text {
                                            width: parent.width
                                            text: modelData.header
                                            color: "#e0af68"
                                            font.pixelSize: 12
                                            font.family: "JetBrains Mono"
                                            font.bold: true
                                            bottomPadding: 2

                                            Rectangle {
                                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                                height: 1
                                                color: "#3b4261"
                                            }
                                        }

                                        // Wiersze skrótów
                                        Repeater {
                                            model: modelData.items

                                            Row {
                                                width: parent.width
                                                spacing: 8

                                                // Skrót (lewa kolumna, stała szerokość)
                                                Rectangle {
                                                    width: 148
                                                    height: keyText.implicitHeight + 4
                                                    color: "#24283b"
                                                    radius: 3

                                                    Text {
                                                        id: keyText
                                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                                                        text: modelData[0]
                                                        color: "#7dcfff"
                                                        font.pixelSize: 10
                                                        font.family: "JetBrains Mono"
                                                    }
                                                }

                                                // Opis (prawa kolumna)
                                                Text {
                                                    width: parent.width - 148 - 8
                                                    anchors.verticalCenter: keyText.parent.verticalCenter
                                                    text: modelData[1]
                                                    color: "#a9b1d6"
                                                    font.pixelSize: 10
                                                    font.family: "JetBrains Mono"
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
