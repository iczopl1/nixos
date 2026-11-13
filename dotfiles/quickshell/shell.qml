// Quickshell bar dla Mango – ThinkPadNIX
// Lewo: tagi (workspace)   Środek: zegar + data   Prawo: cpu | ram | vol | bat | net
// SUPER+D: Vimium hints (Hints.qml + mango-hintd.conf)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // Hints overlay – singletons Mango i BarTargets są auto-odkryte (pragma Singleton)
    Hints {}

    // SUPER+H: overlay z dokumentacją skrótów klawiszowych (T3.1)
    Shortcuts {}

    // WpmBorder i Particles: pragma Singleton – Quickshell auto-odkrywa z katalogu, nie tworzyć ręcznie

    // T2.29: toggle baru przez socket (SUPER+F11) – zamiast kill/restart procesu.
    // kill + restart zostawiał ghost surface w wlr-layer-shell; visible=false unmapuje czysto.
    property bool barVisible: true

    SocketServer {
        id: barToggleServer
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-bar-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket { Component.onCompleted: root.barVisible = !root.barVisible }
    }

    // Rebind po live-reload – czyści stary plik gniazda (jak w Shortcuts.qml)
    Timer {
        interval: 800; running: true
        onTriggered: { barToggleServer.active = false; barToggleServer.active = true }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            visible: root.barVisible

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

                // ===== Media player (T2.34) – playerctl MPRIS =====
                Text {
                    id: mediaLabel
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    color: "#7aa2f7"
                    text: ""
                    visible: false
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    Process {
                        id: mediaProc
                        command: ["playerctl", "metadata", "--format",
                                  "{{artist}} – {{title}}"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const s = line.trim()
                                mediaLabel.visible = s.length > 0
                                // ogranicz do 40 znaków żeby pasek nie pękał
                                mediaLabel.text = s.length > 40 ? s.slice(0, 38) + "…" : s
                            }
                        }
                        onExited: code => { if (code !== 0) mediaLabel.visible = false }
                    }

                    Timer {
                        interval: 3000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: { mediaProc.running = false; mediaProc.running = true }
                    }
                }

                Item { width: 10; visible: mediaLabel.visible }

                // ===== Temperatura CPU (T2.33) – najwyższa strefa thermal =====
                Text {
                    id: tempLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "tmp --"

                    Process {
                        id: tempProc
                        // Czyta wszystkie thermal_zone*/temp, bierze maksimum
                        command: ["/bin/sh", "-c",
                            "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null " +
                            "| awk 'BEGIN{m=0} {v=$1+0; if(v>m)m=v} END{print int(m/1000)}'"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const t = parseInt(line.trim())
                                if (isNaN(t) || t <= 0) return
                                tempLabel.text  = t + "°C"
                                tempLabel.color = t >= 85 ? "#f7768e"
                                              : t >= 70  ? "#e0af68"
                                              :            "#a9b1d6"
                            }
                        }
                    }

                    Timer {
                        interval: 3000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: { tempProc.running = false; tempProc.running = true }
                    }
                }

                Item { width: 10 }

                // ===== FPS (klatki compositora – FrameAnimation zlicza każdy vsync) =====
                Text {
                    id: fpsLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "fps --"

                    property int  _frames: 0
                    property real _t0:     Date.now()

                    FrameAnimation {
                        running: true
                        onTriggered: {
                            fpsLabel._frames++
                            var now = Date.now()
                            if (now - fpsLabel._t0 >= 1000) {
                                var fps = Math.round(fpsLabel._frames * 1000 / (now - fpsLabel._t0))
                                fpsLabel.text  = "fps " + fps
                                fpsLabel.color = fps < 50 ? "#f7768e"
                                              : fps < 55 ? "#e0af68"
                                              :            "#a9b1d6"
                                fpsLabel._frames = 0
                                fpsLabel._t0     = now
                            }
                        }
                    }
                }

                Item { width: 10 }

                // ===== CPU (T2.25) =====
                Text {
                    id: cpuLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "cpu --"

                    property var prevCpu: null

                    Process {
                        id: cpuProc
                        command: ["/bin/sh", "-c", "head -1 /proc/stat"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const parts = line.trim().split(/\s+/)
                                if (parts[0] !== "cpu") return
                                const vals = parts.slice(1).map(Number)
                                if (cpuLabel.prevCpu) {
                                    const prev     = cpuLabel.prevCpu
                                    const idle     = vals[3] + vals[4]
                                    const prevIdle = prev[3] + prev[4]
                                    const total    = vals.reduce((a, b) => a + b, 0)
                                    const prevTotal = prev.reduce((a, b) => a + b, 0)
                                    const dTotal   = total - prevTotal
                                    const dIdle    = idle  - prevIdle
                                    const pct = dTotal > 0 ? Math.round((dTotal - dIdle) / dTotal * 100) : 0
                                    cpuLabel.text  = "cpu " + pct + "%"
                                    cpuLabel.color = pct > 80 ? "#f7768e" : pct > 50 ? "#e0af68" : "#a9b1d6"
                                }
                                cpuLabel.prevCpu = vals
                            }
                        }
                    }

                    Timer {
                        interval: 2000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: cpuProc.running = true
                    }
                }

                Item { width: 10 }

                // ===== RAM (T2.25) =====
                Text {
                    id: ramLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "ram --"

                    property int memTotal: 0
                    property int memAvail: -1

                    function refresh() {
                        if (memTotal > 0 && memAvail >= 0) {
                            const pct = Math.round((memTotal - memAvail) / memTotal * 100)
                            text  = "ram " + pct + "%"
                            color = pct > 85 ? "#f7768e" : pct > 70 ? "#e0af68" : "#a9b1d6"
                        }
                    }

                    Process {
                        id: ramProc
                        command: ["/bin/sh", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const m = line.match(/^(\w+):\s+(\d+)/)
                                if (!m) return
                                if (m[1] === "MemTotal")     ramLabel.memTotal = parseInt(m[2])
                                if (m[1] === "MemAvailable") ramLabel.memAvail = parseInt(m[2])
                                ramLabel.refresh()
                            }
                        }
                    }

                    Timer {
                        interval: 3000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: ramProc.running = true
                    }
                }

                Item { width: 12 }

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

                // ===== Bateria (BAT0 + BAT1) =====
                Text {
                    id: batLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "bat --"
                    visible: false

                    Process {
                        id: batProc
                        command: ["/bin/sh", "-c", "~/.config/scripts/bat-status.sh"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const parts = line.trim().split(" ")
                                const pct = parseInt(parts[0])
                                if (isNaN(pct) || pct < 0) return
                                batLabel.visible = true
                                batLabel.text    = "bat " + pct + "%"
                                batLabel.color   = pct <= 15 ? "#f7768e"
                                                 : pct <= 30 ? "#e0af68"
                                                 : "#a9b1d6"
                            }
                        }
                    }

                    Timer {
                        interval: 30000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: batProc.running = true
                    }
                }

                Item { width: 12 }

                // ===== Telefon GrapheneOS – status Tailscale (T3.7) =====
                Text {
                    id: phoneLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#565f89"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "ph ?"
                    visible: false      // ukryty gdy ts-off (Tailscale wylogowany)

                    Process {
                        id: phoneProc
                        command: ["/bin/sh", "-c", "~/.config/scripts/phone-status.sh"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const s = line.trim()
                                if (!s) return
                                if (s === "ts-off") {
                                    phoneLabel.visible = false
                                    return
                                }
                                phoneLabel.visible = true
                                phoneLabel.text    = s === "online" ? "ph ●" : "ph ○"
                                phoneLabel.color   = s === "online" ? "#9ece6a" : "#f7768e"
                            }
                        }
                    }

                    Timer {
                        interval: 30000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: phoneProc.running = true
                    }
                }

                Item { width: 12 }

                // ===== Syncthing (T2.8) =====
                Text {
                    id: syncLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: ""
                    visible: false      // ukryty gdy Syncthing nie działa

                    Process {
                        id: syncProc
                        command: ["/bin/sh", "-c", "~/.config/scripts/syncthing-status.sh"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const s = line.trim()
                                if (!s) return
                                syncLabel.text    = s
                                syncLabel.visible = (s !== "sync off" && s !== "sync ?")
                                syncLabel.color   = s.includes("OK")  ? "#9ece6a"
                                                  : s.includes("off") ? "#565f89"
                                                  : s.includes("%")   ? "#e0af68"
                                                  : "#a9b1d6"
                            }
                        }
                    }

                    Timer {
                        interval: 30000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: syncProc.running = true
                    }
                }

                Item { width: 12 }

                // ===== Sieć ↓↑ (T2.25) =====
                Text {
                    id: netLabel
                    Layout.alignment: Qt.AlignVCenter
                    color: "#a9b1d6"
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    text: "↓0K ↑0K"
                    visible: false          // ukryty do pierwszego pomiaru

                    property var prevNet: null

                    function fmtSpeed(bytesPerSec) {
                        if (bytesPerSec >= 1048576) return (bytesPerSec / 1048576).toFixed(1) + "M"
                        if (bytesPerSec >= 1024)    return Math.round(bytesPerSec / 1024) + "K"
                        return "0K"
                    }

                    Process {
                        id: netProc
                        // Pomija lo, bierze pierwszy interfejs (wlp*, enp*, eth*, eno*)
                        command: ["/bin/sh", "-c", "awk 'NR>2 && !/lo:/{print; exit}' /proc/net/dev"]
                        running: false
                        stdout: SplitParser {
                            onRead: line => {
                                const parts = line.trim().split(/\s+/)
                                if (parts.length < 10) return
                                const rx = parseInt(parts[1])  // bytes received
                                const tx = parseInt(parts[9])  // bytes transmitted
                                if (isNaN(rx) || isNaN(tx)) return
                                if (netLabel.prevNet !== null) {
                                    const dRx = (rx - netLabel.prevNet.rx) / 2.0
                                    const dTx = (tx - netLabel.prevNet.tx) / 2.0
                                    netLabel.text    = "↓" + netLabel.fmtSpeed(dRx) + " ↑" + netLabel.fmtSpeed(dTx)
                                    netLabel.visible = true
                                }
                                netLabel.prevNet = { rx: rx, tx: tx }
                            }
                        }
                    }

                    Timer {
                        interval: 2000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: netProc.running = true
                    }
                }

                Item { width: 10 }

                // ===== WPM – prędkość pisania (T3.5/T3.13) =====
                Text {
                    id: wpmLabel
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                    color: "#565f89"
                    text: ""
                    visible: false

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Timer {
                        interval: 300; running: true; repeat: true
                        onTriggered: {
                            var w = WpmBorder.wpm
                            if (w > 0) {
                                wpmLabel.visible = true
                                wpmLabel.text  = w + " wpm"
                                wpmLabel.color = w >= 70 ? "#f7768e"
                                              : w >= 45 ? "#ff9e64"
                                              : w >= 20 ? "#e0af68"
                                              :           "#9eeaf9"
                            } else {
                                wpmLabel.visible = false
                            }
                        }
                    }
                }

                Item { width: 4 }
            }
        }
    }
}
