// App launcher, a port of the SUPER-tap rofi grid (~/.config/hypr/rofi-app-icon-grid.rosi).
// Runs in the background so opening skips Quickshell's startup. Driven by
// ~/.config/hypr/rofi-super-hold.sh:
//   qs -c launcher ipc call launcher toggle
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string font: "JetBrainsMono Nerd Font"
    property bool shown: false
    property string query: ""

    // launch counts, shared with rofi drun: "<count> <id>.desktop" per line
    property var counts: ({})
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => (counts[key(b)] || 0) - (counts[key(a)] || 0) || a.name.localeCompare(b.name))

    function key(e) {
        return e.id.endsWith(".desktop") ? e.id : e.id + ".desktop";
    }

    FileView {
        id: history
        path: Quickshell.env("HOME") + "/.cache/rofi3.druncache"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const c = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^(\d+) (.+)$/);
                if (m)
                    c[m[2]] = parseInt(m[1]);
            }
            root.counts = c;
        }
    }

    function bump(e) {
        const c = Object.assign({}, counts);
        c[key(e)] = (c[key(e)] || 0) + 1;
        counts = c;
        history.setText(Object.keys(c).sort((a, b) => c[b] - c[a]).map(k => c[k] + " " + k).join("\n") + "\n");
    }
    // every word must appear in the name, generic name or keywords (rofi "normal" matching)
    readonly property var matches: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        return apps.filter(e => {
            const hay = [e.name, e.genericName, ...e.keywords].join(" ").toLowerCase();
            return words.every(w => hay.includes(w));
        });
    }

    function launch(entry) {
        if (entry) {
            bump(entry);
            entry.execute();
        }
        shown = false;
    }

    function toggle() {
        query = "";
        shown = !shown;
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
    }

    // same toggle over a plain socket, ~7ms vs ~55ms for `qs ipc`:
    // every connection toggles, e.g. `socat -u /dev/null UNIX-CONNECT:<path>`
    SocketServer {
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-launcher-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            Component.onCompleted: root.toggle()
        }
    }

    // The surface stays mapped while hidden (see-through, click-through, no
    // keyboard), so opening is one repaint instead of a new surface.
    PanelWindow {
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: root.shown ? backdrop : null }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-launcher"

        // click outside the box closes, like rofi
        MouseArea {
            id: backdrop
            anchors.fill: parent
            onClicked: root.shown = false
        }

        Rectangle {
            visible: root.shown
            anchors.centerIn: parent
            width: 682
            height: box.implicitHeight + 36
            radius: 26
            color: "#F2313B34"
            border { width: 2; color: "#738E7E" }

            MouseArea { anchors.fill: parent }  // keep clicks inside from closing

            Column {
                id: box
                x: 18; y: 18
                width: parent.width - 36
                spacing: 14

                Rectangle {
                    width: parent.width
                    height: 46
                    radius: 18
                    color: "#8055645A"
                    border { width: 2; color: "#8FA89A" }

                    Rectangle {
                        id: prompt
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: label.implicitWidth + 20
                        height: label.implicitHeight + 10
                        radius: height / 2
                        color: "#9AB9A5"
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: "ICONS"
                            color: "#17261d"
                            font { family: root.font; pointSize: 12 }
                        }
                    }

                    TextInput {
                        id: entry
                        anchors { left: prompt.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: root.query
                        onTextEdited: { root.query = text; grid.currentIndex = 0; }
                        color: "#ECEFF4"
                        font { family: root.font; pointSize: 12 }
                        focus: root.shown
                        clip: true

                        Text {
                            visible: !entry.text
                            text: "Search applications"
                            color: "#8DA193"
                            font: entry.font
                        }

                        Keys.onEscapePressed: root.shown = false
                        Keys.onReturnPressed: root.launch(root.matches[grid.currentIndex])
                        Keys.onEnterPressed: root.launch(root.matches[grid.currentIndex])
                        Keys.onLeftPressed: grid.moveCurrentIndexLeft()
                        Keys.onRightPressed: grid.moveCurrentIndexRight()
                        Keys.onUpPressed: grid.moveCurrentIndexUp()
                        Keys.onDownPressed: grid.moveCurrentIndexDown()
                        Keys.onTabPressed: grid.moveCurrentIndexRight()
                    }
                }

                // 6 x 4 grid of icons, scrolls past that
                GridView {
                    id: grid
                    width: parent.width + 12  // the last column's spacing hangs off the edge
                    height: cellHeight * 4
                    cellWidth: (parent.width + 12) / 6
                    cellHeight: 92
                    clip: true
                    interactive: false
                    keyNavigationWraps: false
                    highlightMoveDuration: 0
                    model: root.matches
                    onModelChanged: currentIndex = 0

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool selected: GridView.isCurrentItem
                        width: grid.cellWidth - 12
                        height: grid.cellHeight - 12
                        radius: 16
                        color: selected ? "#F2A5C4AE" : "#8055645A"
                        border { width: 2; color: selected ? "#9AB9A5" : "transparent" }

                        Image {
                            anchors.centerIn: parent
                            width: 51; height: 51
                            sourceSize { width: 51; height: 51 }
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            asynchronous: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                            Accessible.onPressAction: clicked(null)
                            cursorShape: Qt.PointingHandCursor
                            onEntered: grid.currentIndex = index
                            onClicked: root.launch(modelData)
                        }
                    }

                    WheelHandler {
                        onWheel: ev => ev.angleDelta.y < 0 ? grid.moveCurrentIndexDown() : grid.moveCurrentIndexUp()
                    }
                }
            }
        }
    }
}
