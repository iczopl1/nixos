import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import "Markup.js" as Markup

// Capsule bar: same modules and order as the waybar port, icon-first. Labels
// slide out on hover (right side: left click keeps them open).
PanelWindow {
    id: bar

    required property var modelData
    property bool shown: true

    readonly property string wb: "~/.config/waybar"
    readonly property string wbw: "~/.config/waybar/rust/target/release/wbw"
    readonly property var hmon: Hyprland.monitorFor(screen)
    readonly property var mmon: Mango.active ? Mango.monitor(screen.name) : null

    screen: modelData
    visible: shown
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        // lands right under the existing bar (its pills end at y 23 / 26)
        top: Mango.active ? 25 : 23
        left: 14
        right: 14
    }
    implicitHeight: 36
    exclusionMode: ExclusionMode.Ignore   // preview: sits under the old bar, pushes nothing
    Component.onCompleted: {
        BarTargets.origin = Qt.point(margins.left, margins.top);
        BarTargets.screenName = screen.name;
    }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-bar2"

    // ---- tooltip (GTK tooltip look: dark, rounded, below the module) ----
    QtObject {
        id: tips
        property Item target: null
        property string html: ""

        function show(item, h) {
            target = item;
            html = h;
            if (tipWin.visible) {
                tipWin.visible = false;
                tipWin.visible = true;
            } else {
                tipDelay.restart();
            }
        }
        function hide(item) {
            if (item !== target) return;
            tipDelay.stop();
            tipWin.visible = false;
            target = null;
        }
    }

    Timer {
        id: tipDelay
        interval: 500
        onTriggered: if (tips.target) tipWin.visible = true
    }

    PopupWindow {
        id: tipWin
        anchor.item: tips.target
        anchor.rect.y: tips.target ? tips.target.height + 4 : 0
        anchor.rect.width: tips.target ? tips.target.width : 0
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        implicitWidth: tipText.implicitWidth + 20
        implicitHeight: tipText.implicitHeight + 12
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.8)

            Text {
                id: tipText
                x: 10
                y: 6
                text: Theme.icons(tips.html)
                textFormat: Text.RichText
                color: Theme.c("lavender")
                font.family: Theme.font
                font.pixelSize: Theme.fontPx
            }
        }
    }

    // ================================ left =================================
    Row {
        id: left
        anchors.left: parent.left
        height: parent.height

        Cap {
            // hyprland/workspaces (or mango tags)
            Item {
                width: wsRow.width + 2
                height: 18

                Row {
                    id: wsRow
                    x: 1
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter

                    // mango: current tiling layout name, grouped with the tags
                    Item {
                        id: layoutIcon
                        readonly property var names: ({
                            "T": "tile", "S": "scroll", "G": "grid", "M": "mono", "K": "deck",
                            "CT": "c-tile", "RT": "r-tile", "VS": "v-scroll", "VT": "v-tile", "VG": "v-grid",
                            "VK": "v-deck", "DW": "dwindle", "F": "fair", "VF": "v-fair"
                        })
                        readonly property string sym: bar.mmon ? bar.mmon.layout_symbol : ""
                        visible: Mango.active && sym !== ""
                        width: visible ? layoutText.implicitWidth + 8 : 0
                        height: 16

                        Text {
                            id: layoutText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 0.5
                            text: layoutIcon.names[layoutIcon.sym] || layoutIcon.sym
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx
                            color: Theme.c("flow-2")
                        }
                    }

                    Repeater {
                        // plain {id, urgent, active, seen, ws} for Hyprland workspaces or Mango tags
                        model: Mango.active
                            ? (bar.mmon ? bar.mmon.tags.filter(t => t.client_count > 0 || t.is_active)
                                .map(t => ({ id: t.index, urgent: t.is_urgent, active: t.is_active, seen: t.is_active, ws: null })) : [])
                            : Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === bar.hmon).sort((a, b) => a.id - b.id)
                                .map(w => ({ id: w.id, urgent: w.urgent, active: bar.hmon && bar.hmon.activeWorkspace === w,
                                             seen: Hyprland.monitors.values.some(m => m.activeWorkspace === w), ws: w }))

                        Rectangle {
                            id: wsBtn
                            required property var modelData
                            readonly property bool active: modelData.active
                            readonly property bool seen: modelData.seen

                            width: wsLabel.implicitWidth + 12 + 2
                            height: 16
                            color: "transparent"

                            Rectangle {
                                x: 1
                                width: parent.width - 2
                                height: parent.height
                                radius: 8
                                color: wsBtn.modelData.urgent ? Theme.c("flow-12")
                                     : wsBtn.active ? Theme.shade(Theme.c("flow-1"), wsMouse.containsMouse ? 0.7 : 0.6)
                                     : wsMouse.containsMouse ? Theme.alpha(Theme.c("flow-1"), 0.25) : "transparent"
                            }

                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 0.5
                                text: wsBtn.modelData.id
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx
                                font.bold: wsBtn.active
                                color: wsBtn.modelData.urgent ? Theme.c("base")
                                     : (wsBtn.active || wsBtn.seen || wsMouse.containsMouse) ? Theme.c("text")
                                     : Theme.alpha(Theme.c("text"), 0.55)
                            }

                            MouseArea {
                                id: wsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: wsBtn.modelData.ws ? wsBtn.modelData.ws.activate() : Mango.view(wsBtn.modelData.id, bar.screen.name)
                                Accessible.role: Accessible.Button
                                Accessible.name: "workspace " + wsBtn.modelData.id
                                Accessible.onPressAction: clicked(null)
                                Component.onCompleted: BarTargets.add(wsMouse)
                                Component.onDestruction: BarTargets.remove(wsMouse)
                            }
                        }
                    }
                }
            }

            // thin line between the workspaces and the rest
            Item {
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            ScriptChip {
                id: weather
                readonly property var chars: Array.from(Markup.plain(raw))
                exec: bar.wb + "/scripts/weather.sh"
                interval: 900
                onLeft: bar.wb + "/scripts/weather.sh toggle"
                refreshAfterClick: true
                pinnable: true
                pinButton: Qt.RightButton   // left click already switches city
                pinKey: "weather"
                icon: chars.length > 0 ? chars[0] : ""
                iconFont: Theme.font
                label: chars.slice(1).join("").trim()
                fg: Theme.c("flow-2")
                tipper: tips
            }

            ScriptChip {
                id: keymap
                exec: bar.wb + "/scripts/keymap-state.sh keymap"
                onLeft: bar.wb + "/scripts/keymap-toggle.sh"
                iconSvg: "kbd"
                label: "keymap " + (hasClass("on") ? "on" : "off")
                fg: hasClass("on") ? Theme.c("flow-2") : Theme.alpha(Theme.c("overlay2"), 0.6)
                tipper: tips
            }

            ScriptChip {
                id: nosleep
                exec: bar.wb + "/scripts/keymap-state.sh nosleep"
                onLeft: bar.wb + "/scripts/nosleep-toggle.sh"
                iconSvg: "moon"
                label: "nosleep " + (hasClass("on") ? "on" : "off")
                fg: hasClass("on") ? Theme.c("flow-2") : Theme.alpha(Theme.c("overlay2"), 0.6)
                tipper: tips
            }

            // thin line after the toggles
            Item {
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            // hosts: the script's own mark, colored by state: a dot, or battery % / VRAM % when probed
            ScriptChip {
                exec: bar.wbw + " host unitree-g1"
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'unitree-g1' -e " + bar.wb + "/scripts/robot-menu.sh unitree-g1 robot1-ssh"
                onRight: bar.wbw + " host --notify unitree-g1"
                icon: Markup.toHtml(raw)
                iconRich: true
                tipper: tips
            }

            ScriptChip {
                exec: bar.wbw + " host unitree-r1"
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'unitree-r1' -e " + bar.wb + "/scripts/robot-menu.sh unitree-r1 robot2-ssh"
                onRight: bar.wbw + " host --notify unitree-r1"
                icon: Markup.toHtml(raw)
                iconRich: true
                tipper: tips
            }

            ScriptChip {
                exec: bar.wbw + " host gpu-server"
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'ssh gpu-server-ssh' -e ssh gpu-server-ssh"
                onRight: bar.wbw + " host --notify gpu-server"
                icon: Markup.toHtml(raw)
                iconRich: true
                tipper: tips
            }

            // thin line after the hosts
            Item {
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            // clev: idle glows faintly, a run breathes, an ask pulses hard
            ScriptChip {
                id: clev
                exec: bar.wbw + " clev"
                onLeft: bar.wbw + " clev --click L"
                onRight: bar.wbw + " clev --click R"
                icon: Markup.toHtml(raw)
                iconRich: true
                tipper: tips
                readonly property bool idleHover: hasClass("idle") && hovered
                pulse: hasClass("running") || hasClass("confirm")
                pulseMs: hasClass("confirm") ? 600 : 1400
                bg: hasClass("running") ? Theme.mix(Theme.c("base"), Theme.c("flow-1"), 0.08)
                  : hasClass("confirm") ? Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.12)
                  : idleHover ? Theme.mix(Theme.c("base"), Theme.c("flow-6"), 0.22)
                  : "transparent"
                bgB: hasClass("running") ? Theme.mix(Theme.c("base"), Theme.c("flow-10"), 0.26)
                   : Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.45)
            }

            // Claude Code activity: the glyph carries its own colors, the chip its mood
            ScriptChip {
                exec: bar.wbw + " claude"
                onLeft: bar.wbw + " claude --focus"
                icon: Markup.toHtml(raw)
                iconRich: true
                iconFixedW: 14   // the spinner glyphs differ in width
                tipper: tips
                pulse: hasClass("working") || hasClass("waiting")
                pulseMs: hasClass("waiting") ? 900 : 1400
                bg: hasClass("working") ? Theme.mix(Theme.c("base"), Theme.c("flow-3"), 0.12)
                  : hasClass("waiting") ? Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.10)
                  : hasClass("done") ? Theme.mix(Theme.c("base"), Theme.c("green"), 0.18)
                  : "transparent"
                bgB: hasClass("working") ? Theme.mix(Theme.c("base"), Theme.c("flow-10"), 0.26)
                   : Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.38)
            }

            // thin line after Claude
            Item {
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            // music: a note that appears while something plays; the title peeks on a track change
            ScriptChip {
                id: nowPlaying
                property bool peek: false
                exec: bar.wb + "/scripts/now-playing.sh"
                interval: 5
                onLeft: "~/.config/hypr/bgm-power-monitor.sh toggle"
                onRight: "~/.config/hypr/bgm-power-monitor.sh skip"
                onScroll: "~/.config/hypr/bgm-power-monitor.sh skip"
                refreshAfterClick: true
                iconSvg: "note"
                label: Markup.plain(raw)
                open: peek
                fg: hasClass("paused") ? Theme.c("flow-2") : hasClass("stopped") ? Theme.c("overlay2") : Theme.c("flow-3")
                tipper: tips
                onRawChanged: if (raw !== "") {
                    peek = true;
                    peekTimer.restart();
                }

                Timer {
                    id: peekTimer
                    interval: 4000
                    onTriggered: nowPlaying.peek = false
                }
            }

            // tray
            Item {
                width: trayRow.width + 10
                height: 18
                visible: SystemTray.items.values.length > 0

                Row {
                    id: trayRow
                    x: 5
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: SystemTray.items

                        Item {
                            id: trayItem
                            required property var modelData
                            width: 14
                            height: 14

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 14
                                source: {
                                    const i = trayItem.modelData.icon;
                                    if (!i.includes("?path=")) return i;
                                    const [name, path] = i.split("?path=");
                                    return "file://" + path + "/" + name.slice(name.lastIndexOf("/") + 1);
                                }
                            }

                            MouseArea {
                                id: trayMouse
                                Component.onCompleted: BarTargets.add(trayMouse)
                                Component.onDestruction: BarTargets.remove(trayMouse)
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: e => {
                                    const it = trayItem.modelData;
                                    if (e.button === Qt.MiddleButton) {
                                        it.secondaryActivate();
                                    } else if (e.button === Qt.RightButton || it.onlyMenu) {
                                        const p = trayItem.mapToItem(null, 0, trayItem.height);
                                        if (it.hasMenu) it.display(bar, p.x, p.y + 6);
                                    } else {
                                        it.activate();
                                    }
                                }
                                onWheel: e => trayItem.modelData.scroll(e.angleDelta.y, false)
                                Accessible.role: Accessible.Button
                                Accessible.name: trayItem.modelData.tooltipTitle || trayItem.modelData.id
                                Accessible.onPressAction: trayItem.modelData.activate()
                                onContainsMouseChanged: {
                                    const t = trayItem.modelData.tooltipTitle || trayItem.modelData.title;
                                    if (containsMouse && t) tips.show(trayItem, t);
                                    else tips.hide(trayItem);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================ center ===============================
    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
        tipper: tips
    }

    // ================================ right ================================
    // left click pins a label open; the old left actions are on middle click
    Row {
        anchors.right: parent.right
        height: parent.height

        Cap {
            ScriptChip {
                exec: bar.wbw + " mic"
                onMiddle: "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
                onRight: "pavucontrol --tab=2"
                pinnable: true
                pinKey: "mic"
                iconSvg: hasClass("muted") ? "micoff" : "mic"
                label: Markup.plain(raw)
                fg: hasClass("muted") ? Theme.c("overlay2") : Theme.c("base")
                bg: hasClass("muted") ? "transparent" : Theme.c("flow-12")
                tipper: tips
            }

            // wireplumber
            Chip {
                readonly property var sink: Pipewire.defaultAudioSink
                readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
                readonly property int vol: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

                PwObjectTracker {
                    objects: [Pipewire.defaultAudioSink]
                }

                pinnable: true
                pinKey: "volume"
                iconSvg: muted ? "volmute" : vol < 50 ? "vollow" : "vol"
                label: muted ? "muted" : vol + "%"
                fg: muted ? "#3b4252" : Theme.c("flow-5")
                tip: sink ? (sink.description || sink.name) : ""
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["pavucontrol"]) }
                onScrolled: up => Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", up ? "+5%" : "-5%"])
            }

            // bluetooth
            Chip {
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var conn: Bluetooth.devices.values.filter(d => d.connected)
                readonly property var dev: conn.length > 0 ? conn[0] : null

                shown: adapter !== null
                pinnable: true
                pinKey: "bluetooth"
                iconSvg: "bt"
                label: !adapter || !dev || !adapter.enabled ? ""
                    : dev.name + (dev.batteryAvailable ? " " + Math.round(dev.battery * 100) + "%" : "")
                fg: dev && adapter && adapter.enabled ? Theme.c("flow-6") : Theme.alpha(Theme.c("flow-6"), 0.5)
                tip: adapter ? adapter.name + "&nbsp;&nbsp;&nbsp;&nbsp;" + adapter.adapterId + (dev ? "<br><br>" + conn.length + " connected" : "") : ""
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["blueman-manager"]) }
            }

            Chip {
                pinnable: true
                pinKey: "temp"
                iconSvg: "temp"
                label: Sys.tempC + "°C"
                fg: Sys.tempC >= 80 ? Theme.c("red") : Theme.c("flow-7")
                badge: Sys.tempC >= 80 ? Theme.c("red") : "transparent"
                tip: Sys.tempC + "°C"
                tipper: tips
            }

            Chip {
                pinnable: true
                pinKey: "cpu"
                iconSvg: "cpu"
                label: Sys.cpu + "%"
                fg: Theme.c("flow-8")
                tip: "Load: " + Sys.cpu + "%"
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["ghostty", "-e", "htop"]) }
            }

            Chip {
                pinnable: true
                pinKey: "memory"
                iconSvg: "mem"
                label: Sys.memGb.toFixed(2) + "GB"
                fg: Theme.c("flow-9")
                tip: Sys.memGb.toFixed(1) + "GiB used"
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["ghostty", "-e", "htop"]) }
            }

            // battery
            Chip {
                id: battery
                readonly property int cap: Sys.batCap
                readonly property bool charging: Sys.batStatus === "Charging"
                readonly property bool plugged: Sys.batStatus === "Not charging" && Sys.acOnline
                readonly property string level: cap <= 15 ? "bat0" : cap <= 40 ? "bat1" : cap <= 70 ? "bat2" : "bat3"
                readonly property bool warning: cap <= 30 && cap > 15
                readonly property bool critical: cap <= 15

                shown: cap >= 0
                pinnable: true
                pinKey: "battery"
                iconSvg: charging ? "bolt" : plugged ? "plug" : level
                label: cap + "%" + (Sys.batTime !== "" ? "  " + Sys.batTime : "")
                open: critical && !charging
                fg: charging ? Theme.c("flow-9") : critical ? "#bf616a" : warning ? Theme.c("flow-7") : Theme.c("flow-10")
                pulse: critical && !charging
                pulseMs: 500
                fgB: Theme.c("red")
                tip: Sys.batTime !== "" ? Sys.batTime : Sys.batStatus
                tipper: tips
            }

            // thin line before the network
            Item {
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            // replaces "network": icon follows reachability (scripts/net-state.sh)
            ScriptChip {
                exec: bar.wb + "/scripts/net-state.sh"
                onMiddle: "nm-connection-editor"
                pinnable: true
                pinKey: "network"
                iconSvg: "wifi"
                label: Markup.plain(raw)
                fg: hasClass("off") || hasClass("no-internet") ? "#bf616a" : hasClass("no-dns") ? "#ebcb8b" : Theme.c("flow-11")
                tipper: tips
            }
        }
    }
}
