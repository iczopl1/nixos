// Quickshell bar dla Mango – ThinkPadNIX
// Lewo: tagi (workspace)   Środek: zegar + data   Prawo: vol + bat
// SUPER+D: Vimium hints (Hints.qml + mango-hintd.conf)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    // Hints overlay – singletons Mango i BarTargets są auto-odkryte (pragma Singleton)
    Hints {}

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: 28
            color: "#1a1b26"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: bar.height
            WlrLayershell.namespace: "qs-bar"

            // Zarejestruj tę instancję paska w BarTargets (dla SUPER+D hints)
            Component.onCompleted: {
                BarTargets.screenName = bar.screen.name
                BarTargets.screenW    = bar.screen.width
                BarTargets.origin     = Qt.point(0, 0)
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 0

                // ===== Tagi (workspace) =====
                Row {
                    id: tagRow
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    // Dane monitora z Mango IPC (mmsg watch all-monitors)
                    property var monData: Mango.monitor(bar.screen.name)
                    property var tags: monData ? (monData.tags || []) : []
                    property int count: tags.length > 0 ? tags.length : 10

                    Repeater {
                        model: tagRow.count

                        delegate: Rectangle {
                            id: tagBtn
                            required property int index

                            property var    td:         tagRow.tags[index] || null
                            property bool   isActive:   td ? !!td.is_active             : false
                            property bool   hasClients: td ? (td.client_count || 0) > 0 : false
                            property bool   isUrgent:   td ? !!td.is_urgent              : false

                            width: 22; height: 22; radius: 4

                            color: isUrgent  ? "#f7768e"
                                 : isActive  ? "#7aa2f7"
                                 : hasClients ? "#2d3252"
                                 : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: tagBtn.index + 1
                                color: tagBtn.isActive   ? "#ffffff"
                                     : tagBtn.hasClients ? "#a9b1d6"
                                     : "#565f89"
                                font.pixelSize: 11
                                font.family: "JetBrains Mono"
                                font.bold: tagBtn.isActive
                            }

                            MouseArea {
                                id: tagMa
                                anchors.fill: parent
                                onClicked: Mango.view(tagBtn.index + 1, bar.screen.name)
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: tagBtn.opacity = 0.75
                                onExited:  tagBtn.opacity = 1.0

                                Component.onCompleted:  BarTargets.add(tagMa)
                                Component.onDestruction: BarTargets.remove(tagMa)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // ===== Zegar + data =====
                Text {
                    id: clockLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#c0caf5"
                    font.pixelSize: 13
                    font.family: "JetBrains Mono"

                    function fmt() {
                        const d = new Date()
                        const hh = String(d.getHours()).padStart(2, "0")
                        const mm = String(d.getMinutes()).padStart(2, "0")
                        const days  = ["Nie","Pon","Wt","Śr","Czw","Pt","Sob"]
                        const mons  = ["Sty","Lut","Mar","Kwi","Maj","Cze","Lip","Sie","Wrz","Paź","Lis","Gru"]
                        return hh + ":" + mm + "   " + days[d.getDay()] + " " + d.getDate() + " " + mons[d.getMonth()]
                    }
                    text: fmt()

                    Timer {
                        interval: 10000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: clockLabel.text = clockLabel.fmt()
                    }
                }

                Item { Layout.fillWidth: true }

                // ===== Głośność =====
                Text {
                    id: volLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "vol --"

                    Process {
                        id: volProc
                        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const m = line.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                                if (!m) return
                                const pct = Math.round(parseFloat(m[1]) * 100)
                                const muted = !!m[2]
                                volLabel.text  = (muted ? "mute" : "vol") + " " + pct + "%"
                                volLabel.color = muted ? "#565f89" : "#a9b1d6"
                            }
                        }
                    }

                    Timer {
                        interval: 3000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: volProc.running = true
                    }
                }

                Item { width: 12 }

                // ===== Bateria =====
                Text {
                    id: batLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "bat --"
                    visible: false          // ukryty dopóki nie dostaniemy danych

                    property int pct: -1
                    property bool charging: false

                    Process {
                        id: batCapProc
                        command: ["cat", "/sys/class/power_supply/BAT0/capacity"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const v = parseInt(line.trim())
                                if (isNaN(v)) return
                                batLabel.pct     = v
                                batLabel.visible = true
                                batLabel.updateText()
                            }
                        }
                    }

                    Process {
                        id: batStatProc
                        command: ["cat", "/sys/class/power_supply/BAT0/status"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                batLabel.charging = (line.trim() === "Charging" || line.trim() === "Full")
                                batLabel.updateText()
                            }
                        }
                    }

                    function updateText() {
                        if (pct < 0) return
                        const prefix = charging ? "^bat" : "bat"
                        text  = prefix + " " + pct + "%"
                        color = pct <= 15 ? "#f7768e"
                              : pct <= 30 ? "#e0af68"
                              : "#a9b1d6"
                    }

                    Timer {
                        interval: 30000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: { batCapProc.running = true; batStatProc.running = true }
                    }
                }

                Item { width: 4 }
            }
        }
    }
}
