import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
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
    readonly property string wbw: "wbw"
    readonly property var hmon: Hyprland.monitorFor(screen)
    readonly property var mmon: Mango.active ? Mango.monitor(screen.name) : null

    screen: modelData
    visible: shown || leftCap.peeking || rightCap.peeking
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        // mango: pill centred between screen top and window top (was -2: 3px above, 10px below)
        top: Mango.active ? 3 : 0   // 2px more room above the capsules
        left: 14
        right: 14
    }
    implicitHeight: 36
    exclusiveZone: !shown ? 0 : Mango.active ? 19 : 22   // 2px more room below them
    Component.onCompleted: {
        BarTargets.origin = Qt.point(margins.left, margins.top);
        BarTargets.screenName = screen.name;
        BarTargets.screenW = screen.width;
    }
    color: "transparent"
    WlrLayershell.namespace: "quickshell-bar"

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
            id: leftCap
            capName: "left"
            others: [rightCap]
            barShown: bar.shown
            spacing: 1
            // hyprland/workspaces (or mango tags)
            Item {
                objectName: "ws"
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
                            text: (layoutIcon.names[layoutIcon.sym] || layoutIcon.sym).substring(0, 4)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx
                            color: Theme.flowAt((layoutText.mapToItem(null, 0, 0).x + BarTargets.origin.x) / BarTargets.screenW)
                        }
                    }

                    Repeater {
                        // plain {id, urgent, active, seen, ws} for Hyprland workspaces or Mango tags
                        model: Mango.active
                            ? (bar.mmon ? bar.mmon.tags.filter(t => t.index <= 4 || t.client_count > 0)
                                .map(t => ({ id: t.index, urgent: t.is_urgent, active: t.is_active, seen: t.is_active, ws: null })) : [])
                            : Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === bar.hmon).sort((a, b) => a.id - b.id)
                                .map(w => ({ id: w.id, urgent: w.urgent, active: bar.hmon && bar.hmon.activeWorkspace === w,
                                             seen: Hyprland.monitors.values.some(m => m.activeWorkspace === w), ws: w }))

                        Rectangle {
                            id: wsBtn
                            required property var modelData
                            readonly property bool active: modelData.active
                            readonly property bool seen: modelData.seen

                            TextMetrics { id: digitW; text: "0"; font.family: Theme.font; font.pixelSize: Theme.fontPx }
                            readonly property string tagIcon: Mango.active ? ({1: "tag-social", 2: "tag-web", 3: "tag-term", 4: "tag-docs"})[modelData.id] || "" : ""
                            readonly property color tagFg: modelData.urgent ? Theme.c("base")
                                 : (active || seen || wsMouse.containsMouse) ? Theme.normalize(Theme.c("text"), Theme.flowTarget())
                                 : Theme.alpha(Theme.normalize(Theme.c("text"), Theme.flowTarget()), 0.75)

                            width: (tagIcon !== "" ? digitW.width : wsLabel.implicitWidth) + 12 + 2   // icon takes the space of one digit
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

                            Image {
                                visible: wsBtn.tagIcon !== ""
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                source: wsBtn.tagIcon !== "" ? Qt.resolvedUrl("icons/" + wsBtn.tagIcon + ".svg") : ""
                                sourceSize: Qt.size(56, 56)
                                opacity: wsBtn.tagFg.a
                                layer.enabled: visible
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Qt.rgba(wsBtn.tagFg.r, wsBtn.tagFg.g, wsBtn.tagFg.b, 1)
                                }
                            }

                            Text {
                                id: wsLabel
                                visible: wsBtn.tagIcon === ""
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 0.5
                                text: wsBtn.modelData.id
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx
                                font.bold: wsBtn.active
                                color: wsBtn.modelData.urgent ? Theme.c("base")
                                     : (wsBtn.active || wsBtn.seen || wsMouse.containsMouse) ? Theme.normalize(Theme.c("text"), Theme.flowTarget())
                                     : Theme.alpha(Theme.normalize(Theme.c("text"), Theme.flowTarget()), 0.75)
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
                objectName: "sep-a"
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
                objectName: "weather"
                id: weather
                // split by code point: QML's Array.from cuts emoji like 🌧 into two halves
                readonly property var chars: Markup.plain(raw).match(/[\ud800-\udbff][\udc00-\udfff]|[\s\S]/g) || []
                exec: bar.wb + "/scripts/weather.sh"
                interval: 900
                onLeft: bar.wb + "/scripts/weather.sh toggle"
                refreshAfterClick: true
                pinnable: true
                pinButton: Qt.RightButton   // left click already switches city
                pinKey: "weather"
                icon: previewKind !== "" ? ({clear: "☀", partly: "⛅", cloud: "☁", fog: "🌫", drizzle: "☂", rain: "🌧", snow: "❄", storm: "⛈"})[previewKind] || "" : (chars.length > 0 ? chars[0] : "")
                iconFont: Theme.font
                iconPx: 18
                // script prints "icon City 12°C" (12°C = feels like): the temperature sits left of the icon, the city slides out on hover
                readonly property var parts: chars.slice(1).join("").trim().match(/^(.*?)\s+(-?\d+°C)$/)
                prefix: parts ? parts[2].replace("°C", "°") : ""
                label: parts ? parts[1] : chars.slice(1).join("").trim()
                // animated by the weather type, AC only (switch: weatherfx); weather-preview.txt overrides it for previews
                property string previewKind: ""
                readonly property string kind: previewKind !== "" ? previewKind : (hasClass("drizzle") ? "drizzle" : hasClass("clear") ? "clear" : hasClass("partly") ? "partly" : hasClass("cloud") ? "cloud" : hasClass("fog") ? "fog" : hasClass("rain") ? "rain" : hasClass("snow") ? "snow" : hasClass("storm") ? "storm" : "")
                wx: Sys.onAC ? kind : ""
                FileView {
                    path: "/home/iczo/syshelp/power-fx/weather-preview.txt"
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: weather.previewKind = text().trim()
                    onLoadFailed: weather.previewKind = ""
                }
                fg: flowFg
                tipper: tips
            }

            Chip {
                objectName: "phone"
                id: phone
                shown: true
                autoRipple: Sys.onAC
                iconSvg: "phone"
                // a file arrives in ~/sync: its name slides out for 5 s; more arriving meanwhile pile up as "name +N" (N = files so far)
                property int burst: 0
                property string lastName: ""
                property bool lastDel: false
                function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
                open: flashing
                onFlashingChanged: if (!flashing) { burst = 0; lastName = ""; }
                label: flashing && lastName !== "" ? (lastDel ? "<font color=\"#ff5c5c\">" : "") + esc(lastName.length > 28 ? lastName.slice(0, 27) + "…" : lastName) + (burst > 1 ? " +" + burst : "") + (lastDel ? "</font>" : "") : "phone"
                tip: "open th in ~/sync"
                fg: flowFg
                tipper: tips
                onClicked: b => { if (b === Qt.LeftButton) Quickshell.execDetached(["setsid", "sh", "-c", "~/.config/hypr/spawn-alacritty.sh --title phone -e bash -c 'cd ~/sync && exec ~/.local/bin/th'"]) }

                // file finished by Syncthing in ~/sync: label unhides always; shake + ring on AC only.
                // Event-driven: scripts/sync-events.sh long-polls the Syncthing events API, one line per file.
                Process {
                    command: ["sh", "-c", "exec \"$HOME/.config/quickshell/bar/scripts/sync-events.sh\""]
                    running: phone.cfgPhone
                    stdout: SplitParser {
                        onRead: line => {
                            if (line.length < 2) return;
                            if (Sys.onAC) phone.shake();
                            phone.burst += 1;
                            phone.lastDel = line[0] === "-";
                            phone.lastName = line.slice(1).split("/").pop();
                            phone.ping();
                        }
                    }
                }
            }

            Chip {
                objectName: "keymap"
                id: keymap
                readonly property bool on: Mango.keymode !== "clean"
                shown: false
                iconSvg: "kbd"
                label: "keymap " + (on ? "on" : "off")
                tip: "SUPER+TAB keymap: " + (on ? "on" : "off") + " (click to toggle)"
                fg: on ? flowFg : Theme.alpha(Theme.c("overlay2"), 0.6)
                tipper: tips
                onClicked: b => { if (b === Qt.LeftButton) Quickshell.execDetached(["setsid", "sh", "-c", bar.wb + "/scripts/keymap-toggle.sh"]) }
            }

            ScriptChip {
                objectName: "nosleep"
                id: nosleep
                // one short check every 3s instead of a resident watcher
                interval: 3
                exec: "systemd-inhibit --list --no-legend 2>/dev/null | grep -q 'skip next lid close' && echo '{\"text\":\"●\",\"class\":\"on\"}' || echo '{\"text\":\"○\",\"class\":\"off\"}'"
                onLeft: bar.wb + "/scripts/nosleep-toggle.sh"
                iconSvg: "moon"
                label: "nosleep " + (hasClass("on") ? "on" : "off")
                open: flashing   // the label slides out for 5 s when the switch flips (brings a hidden bar's pill up)
                property bool wasOn: false
                onClassesChanged: {
                    const on = hasClass("on");
                    if (on !== wasOn) { wasOn = on; if (live) ping(); }
                }
                fg: hasClass("on") ? flowFg : Theme.alpha(flowFg, 0.3)
                tipper: tips
            }

            // music: a note that appears while something plays; the title peeks on a track change.
            // lyrics.py streams; while a synced lyric line is current the label stays open and shows it.
            ScriptChip {
                objectName: "nowplaying"
                id: nowPlaying
                property bool peek: false
                property string lastRaw: ""
                exec: "python3 " + Quickshell.shellDir + "/scripts/lyrics.py"
                interval: 0
                onLeft: "~/.config/hypr/bgm-power-monitor.sh toggle"
                onRight: "~/.config/hypr/bgm-power-monitor.sh skip"
                onScroll: "~/.config/hypr/bgm-power-monitor.sh skip"
                refreshAfterClick: true
                iconSvg: "note"
                autoRipple: false   // the label changes with every lyric line
                bob: hasClass("playing") && Sys.onAC
                bobWave: true
                labelFade: true   // lyric/caption lines change every few seconds
                // as wide as the free space up to the clock island allows; longer text scrolls left
                maxLabelW: 200
                function fitLabel() {
                    const cap = nowPlaying.parent ? nowPlaying.parent.parent : null;
                    if (!cap || !island || !island.visible) return;
                    const ref = island.parent;
                    const c = cap.mapToItem(ref, 0, 0).x;
                    const i = island.mapToItem(ref, 0, 0).x;
                    const free = c > i ? c - (i + island.width) : i - (c + cap.width);
                    const w = Math.max(60, Math.floor(free - 12 + nowPlaying.reveal * (5 + nowPlaying.labelW) - 5));
                    if (Math.abs(w - maxLabelW) >= 1) maxLabelW = w;
                }
                onRevealChanged: fitLabel()
                Component.onCompleted: fitLabel()
                Connections {
                    target: leftCap
                    function onWidthChanged() { nowPlaying.fitLabel(); }
                }
                Connections {
                    target: rightCap
                    function onWidthChanged() { nowPlaying.fitLabel(); }
                }
                Connections {
                    target: island
                    function onWidthChanged() { nowPlaying.fitLabel(); }
                    function onVisibleChanged() { nowPlaying.fitLabel(); }
                }
                onParentChanged: fitLabel()   // dragged to the other pill
                label: Markup.plain(raw).replace(/^(?:[\u2669-\u266f]|[\ud800-\udbff][\udc00-\udfff]|\s)+/, "")   // the script prefixes a note; the icon already is one
                open: peek || hasClass("lyric")
                fg: hasClass("paused") ? flowFg : hasClass("stopped") ? Theme.c("overlay2") : flowFg
                tipper: tips
                // peek on a new track only (first tooltip line), not on each lyric line
                onClassesChanged: if (raw !== "" && hasClass("playing") && !hasClass("lyric") && rawTip.split("\n")[0] !== lastRaw) {
                    lastRaw = rawTip.split("\n")[0];
                    peek = true;
                    peekTimer.restart();
                }

                Timer {
                    id: peekTimer
                    interval: 4000
                    onTriggered: nowPlaying.peek = false
                }
            }

            // hosts: robot icon colored by state; battery or VRAM percent replaces it when probed
            ScriptChip {
                objectName: "g1"
                id: chip_unitree_g1
                exec: bar.wbw + " host unitree-g1"
                // appears on the tailnet (offline -> online): greet for 5 s
                readonly property bool online: rawTip.indexOf("</b>: online") >= 0
                property int _seen: -1
                property real _lastPing: 0
                // at most one greeting per minute
                onRawTipChanged: {
                    if (rawTip === "") return;
                    if (_seen === 0 && online && Date.now() - _lastPing >= 60000) {
                        _lastPing = Date.now();
                        ping();
                    }
                    _seen = online ? 1 : 0;
                }
                open: flashing
                label: flashing ? "Let's get to work!" : ""
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'unitree-g1' -e " + bar.wb + "/scripts/robot-menu.sh unitree-g1 robot1-ssh"
                onRight: bar.wbw + " host --notify unitree-g1"
                // the robot while there is no reading; the script's number once there is
                readonly property bool hasNumber: /\d/.test(Markup.plain(raw))
                readonly property var m: /color='(#[0-9a-fA-F]+)'/.exec(raw)
                iconSvg: "human"
                iconColor: Theme.ink
                badge: online ? (hasNumber ? "transparent" : "#50fa7b") : rawTip.indexOf("</b>: offline") >= 0 ? "#ff5555" : "transparent"   // dot: green = online, red = offline (hidden while a number shows; none for no route)
                sub: hasNumber ? Markup.plain(raw) : ""
                subColor: m ? m[1] : Theme.ink
                tipper: tips
            }

            ScriptChip {
                objectName: "r1"
                id: chip_unitree_r1
                exec: bar.wbw + " host unitree-r1"
                // appears on the tailnet (offline -> online): greet for 5 s
                readonly property bool online: rawTip.indexOf("</b>: online") >= 0
                property int _seen: -1
                property real _lastPing: 0
                // at most one greeting per minute
                onRawTipChanged: {
                    if (rawTip === "") return;
                    if (_seen === 0 && online && Date.now() - _lastPing >= 60000) {
                        _lastPing = Date.now();
                        ping();
                    }
                    _seen = online ? 1 : 0;
                }
                open: flashing
                label: flashing ? "Let's get to work!" : ""
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'unitree-r1' -e " + bar.wb + "/scripts/robot-menu.sh unitree-r1 robot2-ssh"
                onRight: bar.wbw + " host --notify unitree-r1"
                // the robot while there is no reading; the script's number once there is
                readonly property bool hasNumber: /\d/.test(Markup.plain(raw))
                readonly property var m: /color='(#[0-9a-fA-F]+)'/.exec(raw)
                iconSvg: "r1"
                iconColor: Theme.ink
                badge: online ? (hasNumber ? "transparent" : "#50fa7b") : rawTip.indexOf("</b>: offline") >= 0 ? "#ff5555" : "transparent"   // dot: green = online, red = offline (hidden while a number shows; none for no route)
                sub: hasNumber ? Markup.plain(raw) : ""
                subColor: m ? m[1] : Theme.ink
                tipper: tips
            }

            ScriptChip {
                objectName: "gpulab"
                exec: bar.wbw + " host gpu-server"
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'ssh gpu-server-ssh' -e ssh gpu-server-ssh"
                onRight: bar.wbw + " host --notify gpu-server"
                // the robot while there is no reading; the script's number once there is
                readonly property bool hasNumber: /\d/.test(Markup.plain(raw))
                readonly property var m: /color='(#[0-9a-fA-F]+)'/.exec(raw)
                iconSvg: "server"
                iconColor: Theme.ink
                badge: rawTip.indexOf("</b>: offline") >= 0 ? "#ff5555" : rawTip.indexOf("</b>: online") < 0 ? "transparent" : hasNumber ? "transparent" : "#50fa7b"   // dot: green = online, red = offline (hidden while a number shows; none for no route)
                sub: hasNumber ? Markup.plain(raw) : ""
                subColor: m ? m[1] : Theme.ink
                tipper: tips
            }

            // my-pc is not on the tailnet, so wbw host can't probe it: ping it instead.
            // Left click = ~/bin/rd (moonlight stream to my-pc; disconnects BT controllers on close).
            ScriptChip {
                objectName: "my-pc"
                exec: "if ping -c1 -W2 my-pc >/dev/null 2>&1; then echo '{\"text\":\"up\",\"tooltip\":\"<b>my-pc</b>: reachable\\nleft click: moonlight stream (rd)\"}'; else echo '{\"text\":\"down\",\"tooltip\":\"<b>my-pc</b>: no ping reply\\nleft click: moonlight stream (rd)\"}'; fi"
                interval: 15
                onLeft: "~/bin/rd >/dev/null 2>&1"
                iconSvg: "gamepad"
                iconColor: raw === "up" ? Theme.ink : "#808080"
                badge: raw === "up" ? "#50fa7b" : raw === "down" ? "#ff5555" : "transparent"   // dot: green = online, red = offline (hidden while a number shows; none for no route)
                tipper: tips
            }

            ScriptChip {
                objectName: "my-pc-ssh"
                exec: bar.wbw + " host my-pc"
                // left click: menu with shell (ssh my-pc-ssh) and moonlight (remote desktop)
                onLeft: "~/.config/hypr/spawn-alacritty.sh --title 'my-pc' -e " + bar.wb + "/scripts/pc-menu.sh my-pc my-pc-ssh"
                onRight: bar.wbw + " host --notify my-pc"
                // the monitor glyph while there is no reading; the CPU % once there is one
                readonly property bool hasNumber: /\d/.test(Markup.plain(raw))
                readonly property var m: /color='(#[0-9a-fA-F]+)'/.exec(raw)
                iconSvg: "monitor"
                iconColor: Theme.ink
                badge: rawTip.indexOf("</b>: offline") >= 0 ? "#ff5555" : rawTip.indexOf("</b>: online") < 0 ? "transparent" : hasNumber ? "transparent" : "#50fa7b"   // dot: green = online, red = offline (hidden while a number shows; none for no route)
                sub: hasNumber ? Markup.plain(raw) : ""
                subColor: m ? m[1] : Theme.ink
                tipper: tips
            }

            // clev: idle glows faintly, a run breathes, an ask pulses hard
            ScriptChip {
                objectName: "clev"
                id: clev
                autoRipple: false
                exec: bar.wbw + " clev"
                onLeft: bar.wbw + " clev --click L"
                onRight: bar.wbw + " clev --click R"
                // idle: a sparkle; running/asking keep the script's own glyph
                icon: hasClass("idle") ? "" : Markup.toHtml(raw.replace(/color='#[0-9a-fA-F]{6}'/g, "color='" + flowFg + "'"))
                iconRich: true
                iconSvg: hasClass("idle") ? "sparkle" : ""
                fg: flowFg
                tipper: tips
                pulse: hasClass("running") || hasClass("confirm")
                pulseMs: hasClass("confirm") ? 600 : 1400
                bg: hasClass("running") ? Theme.mix(Theme.c("base"), Theme.c("flow-1"), 0.08)
                  : hasClass("confirm") ? Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.12)
                  : "transparent"
                bgB: hasClass("running") ? Theme.mix(Theme.c("base"), Theme.c("flow-10"), 0.26)
                   : Theme.mix(Theme.c("base"), Theme.c("flow-12"), 0.45)
            }

            // Claude Code activity: ONE glyph, for the most important session: question > finished > running > idle; no pulsing background
            ScriptChip {
                objectName: "claude"
                id: claudeChip
                autoRipple: false
                exec: bar.wbw + " claude"
                iconPx: 17   // the spinner glyphs sit small in their em box; match the 14px line icons
                iconDy: -1.5
                onLeft: bar.wbw + " claude --focus"

                // the script prints one glyph per session, and the tooltip one row per session in the same order;
                // the row's marker says the state: ◆ question, ✓ finished, ● running, ○ idle, ◌ unknown
                readonly property var glyphs: raw.match(/<span font_family='[^']*'>.*?<\/span><\/span>/g) || []
                readonly property var marks: {
                    const out = [], re = /<span color='[^']*'>([\u25c6\u25cf\u2713\u25cb\u25cc?])<\/span> <b>/g;
                    let m;
                    while ((m = re.exec(rawTip)) !== null) out.push(m[1]);
                    return out;
                }
                readonly property int pickIdx: {
                    const order = ["\u25c6", "\u2713", "\u25cf", "\u25cb", "\u25cc"];
                    for (const mk of order) {
                        const i = marks.indexOf(mk);
                        if (i >= 0 && i < glyphs.length) return i;
                    }
                    return 0;
                }
                readonly property string shown1: marks[pickIdx] === "\u25c6" ? "waiting" : marks[pickIdx] === "\u2713" ? "done"
                                               : marks[pickIdx] === "\u25cf" ? "working" : "idle"

                icon: glyphs.length > 0 ? Markup.toHtml(glyphs[pickIdx].replace(/color='#[0-9a-fA-F]{6}'/g, "color='" + flowFg + "'")) : ""
                iconRich: true
                iconFixedW: 12   // always one glyph: fixed width so the spinner does not jiggle the bar
                tipper: tips
            }

            // thin line after Claude
            Item {
                objectName: "sep-b"
                width: 7
                height: 18

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 12
                    color: Theme.alpha(Theme.c("text"), 0.25)
                }
            }

            // tray
            Item {
                objectName: "tray"
                width: trayRow.width
                height: 18
                visible: SystemTray.items.values.some(i => !/blueman/i.test(i.id + " " + i.title + " " + i.icon))

                Row {
                    id: trayRow
                    spacing: 1
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: SystemTray.items

                        Item {
                            id: trayItem
                            required property var modelData
                            // blueman-applet duplicates the bluetooth chip
                            visible: !/blueman/i.test(modelData.id + " " + modelData.title + " " + modelData.icon)
                            width: 26   // same footprint as a Chip
                            height: 18

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 14
                                source: {
                                    const i = trayItem.modelData.icon;
                                    if (!i.includes("?path=")) return i;
                                    const [name, path] = i.split("?path=");
                                    return "file://" + path + "/" + name.slice(name.lastIndexOf("/") + 1);
                                }
                                // monochrome: grayscale (detail kept), lifted so it reads as bright as the other modules
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    saturation: -1.0
                                    brightness: 0.35
                                    contrast: 0.15
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
        id: island
        visible: bar.shown
        anchors.horizontalCenter: parent.horizontalCenter
        tipper: tips
    }

    // ================================ right ================================
    // left click pins a label open; the old left actions are on middle click
    Row {
        anchors.right: parent.right
        height: parent.height

        Cap {
            id: rightCap
            capName: "right"
            others: [leftCap]
            barShown: bar.shown
            Chip {
                objectName: "mic"
                shown: Mic.active
                onClicked: b => {
                    if (b === Qt.MiddleButton) Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                    else if (b === Qt.RightButton) Quickshell.execDetached(["pavucontrol", "--tab=2"]);
                }
                pinnable: true
                pinKey: "mic"
                iconSvg: Mic.muted ? "micoff" : "mic"
                label: Mic.label
                tip: Mic.tooltip
                fg: Mic.muted ? Theme.c("overlay2") : Theme.c("base")
                bg: Mic.muted ? "transparent" : Theme.c("flow-12")
                tipper: tips
            }

            // wireplumber
            Chip {
                objectName: "volume"
                id: volChip
                autoRipple: false
                readonly property var sink: Pipewire.defaultAudioSink
                readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
                readonly property int vol: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

                PwObjectTracker {
                    objects: [Pipewire.defaultAudioSink]
                }

                // power-fx style ripple: a ring spreads from the chip when the volume or mute changes
                property bool rippleReady: false
                property real rp: 1
                property int rdir: 1        // 1: volume up, the ring spreads out; -1: volume down or mute, the ring shrinks in
                property real prevVol: -1
                Timer { interval: 2500; running: true; onTriggered: volChip.rippleReady = true }
                NumberAnimation { id: rippleAnim; target: volChip; property: "rp"; from: 0; to: 1; duration: volChip.rdir > 0 ? 520 : 300; easing.type: Easing.OutCubic }
                open: flashing   // the label slides out for 5 s whenever the volume or mute changes
                onVolChanged: {
                    if (rippleReady) ping();
                    if (rippleReady && cfgVol && Sys.onAC) {
                        rdir = (prevVol < 0 || vol >= prevVol) ? 1 : -1;
                        rippleAnim.restart();
                    }
                    prevVol = vol;
                }
                onMutedChanged: if (rippleReady) {
                    ping();
                    if (cfgVol && Sys.onAC) {
                        rdir = muted ? -1 : 1;
                        rippleAnim.restart();
                    }
                }
                Rectangle {
                    visible: volChip.rp < 1
                    width: 16 + 70 * (volChip.rdir > 0 ? volChip.rp : 1 - volChip.rp)
                    height: width
                    radius: width / 2
                    x: volChip.width / 2 - width / 2
                    y: volChip.height / 2 - height / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.c("flow-3")
                    opacity: (volChip.rdir > 0 ? (1 - volChip.rp) : (1 - volChip.rp * volChip.rp)) * 0.9
                    z: 10
                }
                pinnable: true
                pinKey: "volume"
                iconSvg: muted ? "volmute" : vol < 50 ? "vollow" : "vol"
                label: muted ? "muted" : vol + "%"
                fg: muted ? "#3b4252" : flowFg
                tip: sink ? (sink.description || sink.name) : ""
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["pavucontrol"]) }
                onScrolled: up => Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", up ? "+5%" : "-5%"])
            }

            // bluetooth
            Chip {
                objectName: "bluetooth"
                id: parent_bt
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var conn: Bluetooth.devices.values.filter(d => d.connected)
                readonly property var dev: conn.length > 0 ? conn[0] : null

                readonly property bool on: adapter !== null && adapter.enabled
                property bool ready: false
                Timer { interval: 2500; running: true; onTriggered: parent_bt.ready = true }
                // the label slides out for 5 s when bluetooth is switched or a device connects / disconnects
                onOnChanged: if (ready) ping()
                onDevChanged: if (ready) ping()
                // every newly connected device (not only the first one) unhides the chip and shows its name;
                // a device that disconnects shows its name in red
                property var seen: []
                property string newName: ""
                property string goneName: ""
                onConnChanged: {
                    const fresh = conn.find(d => !seen.some(o => o.address === d.address));
                    const gone = seen.find(o => !conn.some(d => d.address === o.address));
                    newName = ready && fresh ? fresh.name : "";
                    goneName = ready && !fresh && gone ? gone.name : "";
                    if (ready && (fresh || gone)) ping();
                    seen = conn.map(d => ({ address: d.address, name: d.name }));
                }
                open: flashing

                shown: adapter !== null
                pinnable: true
                pinKey: "bluetooth"
                iconSvg: "bt"
                label: !adapter ? ""
                    : !on ? (flashing ? "off" : "")
                    : flashing && newName !== "" ? newName
                    : flashing && goneName !== "" ? "<font color=\"#ff5c5c\">" + goneName.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>"
                    : !dev ? (flashing ? "no device" : "")
                    : dev.name + (dev.batteryAvailable ? " " + Math.round(dev.battery * 100) + "%" : "")
                fg: dev && adapter && adapter.enabled ? flowFg : Theme.alpha(flowFg, 0.5)
                tip: adapter ? adapter.name + "&nbsp;&nbsp;&nbsp;&nbsp;" + adapter.adapterId + (dev ? "<br><br>" + conn.length + " connected" : "") : ""
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["blueman-manager"]) }
            }

            // monitor manager (menus/Display.qml): click opens it
            Chip {
                objectName: "display"
                iconSvg: "display"
                tip: "Displays"
                tipper: tips
                onClicked: b => Quickshell.execDetached(["socat", "-u", "/dev/null",
                    "UNIX-CONNECT:" + Quickshell.env("XDG_RUNTIME_DIR") + "/qs-menu-display-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"])
            }

            Chip {
                objectName: "temp"
                pinnable: true
                pinKey: "temp"
                iconSvg: "temp"
                autoRipple: false
                label: Sys.tempC + "°C"
                fg: Sys.tempC >= 80 ? Theme.c("red") : flowFg
                badge: Sys.tempC >= 80 ? Theme.c("red") : "transparent"
                tip: Sys.tempC + "°C"
                tipper: tips
            }

            Chip {
                objectName: "cpu"
                id: cpuChip
                pinnable: true
                pinKey: "cpu"
                open: flashing || Sys.cpu >= 60
                property int _prev: 0
                Connections {
                    target: Sys
                    function onCpuChanged() {
                        if (cpuChip._prev < 10 && Sys.cpu >= 10 || cpuChip._prev < 20 && Sys.cpu >= 20) cpuChip.ping();
                        cpuChip._prev = Sys.cpu;
                    }
                }
                autoRipple: false
                iconSvg: "cpu"
                label: Sys.cpu + "%"
                fg: flowFg
                tip: "Load: " + Sys.cpu + "%"
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["ghostty", "-e", "htop"]) }
            }

            Chip {
                objectName: "memory"
                id: memChip
                pinnable: true
                pinKey: "memory"
                open: flashing || Sys.memGb >= 7
                property real _prev: 0
                Connections {
                    target: Sys
                    function onMemGbChanged() {
                        // rose past 3 GB or 5 GB: show 5 s
                        if (memChip._prev < 3 && Sys.memGb >= 3 || memChip._prev < 5 && Sys.memGb >= 5) memChip.ping();
                        memChip._prev = Sys.memGb;
                    }
                }
                autoRipple: false
                iconSvg: "mem"
                label: Sys.memGb.toFixed(2) + "GB"
                fg: flowFg
                // top 5 programs by RAM (all processes of one name summed), refreshed on each hover
                property string topProcs: ""
                onHoveredChanged: if (hovered && !topProc.running) topProc.running = true
                Process {
                    id: topProc
                    command: ["sh", "-c", "ps -eo rss=,comm= | awk '{r=$1; $1=\"\"; n=substr($0,2); sub(/^\\./,\"\",n); sub(/-wr[a-z]*$/,\"\",n); gsub(/[<>&]/,\"\",n); m[n]+=r} END{for(k in m) printf \"%d %s\\n\", m[k], k}' | sort -rn | head -5 | awk '{r=$1; $1=\"\"; printf \"%s%-16s %5.2f GB\", (NR>1?\"<br>\":\"\"), substr($0,2), r/1048576}'"]
                    stdout: StdioCollector { onStreamFinished: memChip.topProcs = text }
                }
                tip: Sys.memGb.toFixed(1) + "GiB used" + (topProcs !== "" ? "<br>" + topProcs : "")
                tipper: tips
                onClicked: b => { if (b === Qt.MiddleButton) Quickshell.execDetached(["ghostty", "-e", "htop"]) }
            }

            // battery
            Chip {
                objectName: "battery"
                id: battery
                autoRipple: false
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
                open: flashing || (cap >= 0 && cap <= 10 && !charging && !plugged)
                property int _prev: 101
                Connections {
                    target: Sys
                    function onBatCapChanged() {
                        // on battery and fell to 50% or 20%: show 5 s
                        if (Sys.batStatus === "Discharging" && Sys.batCap >= 0
                                && (battery._prev > 50 && Sys.batCap <= 50 || battery._prev > 20 && Sys.batCap <= 20))
                            battery.ping();
                        battery._prev = Sys.batCap;
                    }
                }
                fg: charging ? flowFg : critical ? "#bf616a" : warning ? Theme.c("flow-7") : flowFg
                pulse: critical && !charging
                pulseMs: 500
                fgB: Theme.c("red")
                tip: Sys.batTime !== "" ? Sys.batTime : Sys.batStatus
                tipper: tips
            }

            // thin line before the network
            Item {
                objectName: "sep-c"
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
                objectName: "net"
                id: net
                exec: bar.wb + "/scripts/net-state.sh --once"
                // same cadence net-state.sh used: 30s online, 5s degraded, 60s off
                interval: hasClass("online") ? 30 : hasClass("off") ? 60 : 5
                Connections {
                    target: NetWatch
                    function onChanged() { net.refresh(); }
                }
                onMiddle: "nm-connection-editor"
                pinnable: true
                pinKey: "network"
                iconSvg: hasClass("no-radio") ? "wifi-noradio" : hasClass("off") ? "wifi-off" : hasClass("no-internet") ? "wifi-nonet" : hasClass("no-dns") ? "wifi-nodns" : "wifi"
                keepColor: hasClass("off") || hasClass("no-internet") || hasClass("no-dns")
                label: Markup.plain(raw)
                fg: hasClass("off") || hasClass("no-internet") ? "#bf616a" : hasClass("no-dns") ? "#ebcb8b" : flowFg
                tipper: tips
            }
        }
    }
}
