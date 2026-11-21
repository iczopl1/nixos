import QtQuick
import Quickshell
import Quickshell.Io

// SUPER+F10 wallpaper sheet: 6x3 square previews, 2px gaps, 2px padding, no rounded corners, no text.
// The menu color is the wal background of the current wallpaper (~/.cache/wal/colors.json).
// `rofi-wallpaper-switcher.sh --list` (scan, thumbnails, hue sort) runs at startup and after
// each close, so the grid is ready when opened and never reorders while you look at it.
Rectangle {
    id: root

    required property var screenItem  // for the 80% window width
    signal close

    readonly property int columns: 6
    readonly property int lines: 3
    readonly property int gap: 2
    property var items: []
    property var lastPointer: null  // global pointer position seen since opening

    // the last wallpaper applied, marked in the grid
    readonly property string current: lastWallpaper.text().trim()

    function open() {
        lastPointer = null;
        view.currentIndex = 0;
        view.positionViewAtBeginning();
        keys.forceActiveFocus();
    }

    function pick() {
        const i = view.currentIndex;
        if (i < 0 || i >= items.length)
            return;
        close();
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/switch-random-wallpaper.sh", items[i].path]);
    }

    // square cells: width from 80% of the screen, capped so three rows fit in 90% of its height
    readonly property real cell: Math.floor(Math.min(
        (screenItem.width * 0.8 - 2 * gap - (columns - 1) * gap) / columns,
        (screenItem.height * 0.9 - 2 * gap - (lines - 1) * gap) / lines))

    width: columns * cell + (columns - 1) * gap + 2 * gap
    height: lines * cell + (lines - 1) * gap + 2 * gap
    radius: 0
    color: wal.adapter.special.background
    Behavior on color { ColorAnimation { duration: 400 } }

    FileView {
        id: wal
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        adapter: JsonAdapter {
            property JsonObject special: JsonObject { property string background: "#101114" }
        }
    }

    FileView {
        id: lastWallpaper
        path: Quickshell.env("HOME") + "/.cache/hypr-last-wallpaper"
        watchChanges: true
        onFileChanged: reload()
    }

    Process {
        id: list
        running: true
        command: [Quickshell.env("HOME") + "/.config/hypr/rofi-wallpaper-switcher.sh", "--list"]
        stdout: StdioCollector {
            onStreamFinished: root.items = text.split("\n").filter(l => l.includes("\t")).map(l => {
                const [path, thumb] = l.split("\t");
                return { icon: "file://" + thumb, path: path };
            })
        }
    }

    onVisibleChanged: if (!visible) list.running = true

    MouseArea { anchors.fill: parent }  // keep clicks inside from closing
    HoverHandler { id: hover }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.pick()
        Keys.onEnterPressed: root.pick()
        Keys.onTabPressed: view.currentIndex = Math.min(view.currentIndex + 1, view.count - 1)
        Keys.onBacktabPressed: view.currentIndex = Math.max(view.currentIndex - 1, 0)
        Keys.onPressed: ev => {
            const page = root.lines * root.columns;
            if (ev.key === Qt.Key_Left) view.moveCurrentIndexLeft();
            else if (ev.key === Qt.Key_Right) view.moveCurrentIndexRight();
            else if (ev.key === Qt.Key_Up) view.moveCurrentIndexUp();
            else if (ev.key === Qt.Key_Down) view.moveCurrentIndexDown();
            else if (ev.key === Qt.Key_PageDown) view.currentIndex = Math.min(view.currentIndex + page, view.count - 1);
            else if (ev.key === Qt.Key_PageUp) view.currentIndex = Math.max(view.currentIndex - page, 0);
            else return;
            ev.accepted = true;
        }
    }

    GridView {
        id: view
        x: root.gap; y: root.gap
        // whole cells, or GridView drops a column: the last column's gap hangs off the edge
        width: root.columns * (root.cell + root.gap)
        height: root.lines * (root.cell + root.gap)
        cellWidth: root.cell + root.gap
        cellHeight: root.cell + root.gap
        clip: true
        interactive: false
        highlightMoveDuration: 0
        model: root.items

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool selected: GridView.isCurrentItem
            width: root.cell
            height: root.cell

            Image {
                anchors.fill: parent
                sourceSize { width: root.cell; height: root.cell }
                fillMode: Image.PreserveAspectCrop
                source: tile.modelData.icon
                asynchronous: true
            }

            // dim the others while the pointer is over the menu
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: hover.hovered && !tile.selected ? 0.3 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Rectangle {
                anchors.fill: parent
                visible: tile.selected
                color: "transparent"
                border { width: 2; color: "white" }
            }

            // current wallpaper
            Rectangle {
                visible: tile.modelData.path === root.current
                x: 6; y: 6; width: 7; height: 7
                color: "white"
                border { width: 2; color: "#99000000" }
            }

            MenuHint {
                anchors.fill: parent
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: String(tile.modelData.path).split("/").pop()
                Accessible.onPressAction: clicked(null)
                cursorShape: Qt.PointingHandCursor
                // select on real pointer motion only: not when the menu opens or
                // scrolls under a resting pointer (that would steal the keyboard pick)
                onPositionChanged: mouse => {
                    const g = mapToGlobal(mouse.x, mouse.y);
                    const last = root.lastPointer;
                    root.lastPointer = g;
                    if (last && (last.x !== g.x || last.y !== g.y))
                        view.currentIndex = tile.index;
                }
                onClicked: { view.currentIndex = tile.index; root.pick(); }
            }
        }

        WheelHandler {
            onWheel: ev => ev.angleDelta.y < 0 ? view.moveCurrentIndexDown() : view.moveCurrentIndexUp()
        }
    }
}
