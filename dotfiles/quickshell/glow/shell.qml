import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Soft glow behind the focused mango window, in the wal focus color.
// Lives on the top layer, click-through; the window's own area is masked out. Started/stopped by mango/power-fx.sh on AC.
ShellRoot {
    id: root

    property var client: null
    property var monitors: []
    property color glow: "#dadfff"
    readonly property int spread: 48

    // focus_color=0xRRGGBBAA from the wal theme
    FileView {
        path: Quickshell.env("HOME") + "/.config/mango/mango-wal.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^focus_color=0x([0-9a-fA-F]{6})/m);
            if (m) root.glow = "#" + m[1];
        }
    }

    Process {
        running: true
        command: ["mmsg", "watch", "focusing-client"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.client = JSON.parse(line);
                } catch (e) {}
            }
        }
    }

    // Active tags per monitor. The glow hides the moment the tag changes, instead
    // of lingering until the next focusing-client event arrives.
    Process {
        running: true
        command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.monitors = JSON.parse(line).monitors || [];
                } catch (e) {}
            }
        }
    }

    function onActiveTag(c) {
        const m = monitors.find(x => x.name === c.monitor);
        return !!m && (m.tags || []).some(t => t.is_active && c.tags.indexOf(t.index) !== -1);
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "mango-glow"
            color: "transparent"
            mask: Region {}

            readonly property bool show: root.client !== null
                && root.client.monitor === modelData.name
                && root.client.is_visible && !root.client.is_fullscreen
                && root.onActiveTag(root.client)

            // Container = window rect plus `spread` on every side. A thin ring is
            // blurred outward, then the window's own area is masked away so the
            // glow tints only what is outside the window.
            Item {
                id: halo
                opacity: win.show ? 1 : 0
                visible: opacity > 0
                readonly property int pad: root.spread
                x: (root.client ? root.client.x - win.modelData.x : 0) - pad
                y: (root.client ? root.client.y - win.modelData.y : 0) - pad
                width: (root.client ? root.client.width : 0) + 2 * pad
                height: (root.client ? root.client.height : 0) + 2 * pad


                Rectangle {
                    id: ring
                    anchors.fill: parent
                    anchors.margins: halo.pad - 2
                    radius: 12
                    color: "transparent"
                    border.width: 16
                    border.color: root.glow
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: root.spread
                        blur: 1.0
                        maskEnabled: true
                        maskInverted: true
                        maskSource: hole
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Item {
                    id: hole
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: halo.pad
                        radius: 10
                        color: "black"
                    }
                }
            }
        }
    }
}
