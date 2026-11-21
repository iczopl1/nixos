import QtQuick
import Quickshell
import Quickshell.Io

// SUPER+SHIFT+F10: search wallhaven as you type (1920x1080+, SFW); square previews like SUPER+F10;
// Enter/click on one downloads it to ~/wpps and applies it. Esc closes.
Rectangle {
    id: root

    required property var screenItem
    signal close

    readonly property string font: "JetBrains Mono"
    readonly property int columns: 6
    readonly property int lines: 3
    readonly property int gap: 2
    readonly property int barH: 52
    property var items: []
    property string status: "Type to search"
    property string wanted: ""     // latest query typed
    property string runQuery: ""   // query the running search was started for
    property var lastPointer: null
    property int page: 1
    property bool hasMore: false
    readonly property int pageSize: 24

    function parse(text) {
        return text.split("\n").filter(l => l.includes("\t")).map(l => {
            const [id, url, thumb, res] = l.split("\t");
            return { id: id, url: url, icon: "file://" + thumb, res: res };
        });
    }

    // selection reached the last row: fetch the next page
    function maybeMore() {
        if (!hasMore || more.running || fetch.running || runQuery !== wanted)
            return;
        if (view.currentIndex < items.length - columns)
            return;
        more.page = page + 1;
        more.command = [Quickshell.env("HOME") + "/.config/hypr/wallhaven-search.sh", runQuery, String(more.page)];
        more.query = runQuery;
        more.running = true;
    }

    // same square cells as the SUPER+F10 sheet
    readonly property real cell: Math.floor(Math.min(
        (screenItem.width * 0.8 - 2 * gap - (columns - 1) * gap) / columns,
        (screenItem.height * 0.9 - barH - 2 * gap - (lines - 1) * gap) / lines))

    function open() {
        entry.text = "";
        items = [];
        status = "Type to search";
        wanted = "";
        lastPointer = null;
        debounce.stop();
        entry.forceActiveFocus();
    }

    // search as you type: wait for a pause, restart if the text changed meanwhile
    function typed() {
        wanted = entry.text.trim();
        if (wanted.length < 2) {
            debounce.stop();
            items = [];
            status = "Type to search";
            return;
        }
        debounce.restart();
    }

    function startSearch() {
        if (wanted.length < 2 || fetch.running)
            return;
        runQuery = wanted;
        more.running = false;
        page = 1;
        hasMore = false;
        status = "Searching…";
        fetch.command = [Quickshell.env("HOME") + "/.config/hypr/wallhaven-search.sh", runQuery];
        fetch.running = true;
    }

    function toTiles() {
        if (debounce.running) {  // search the pending text now
            debounce.stop();
            if (fetch.running) fetch.running = false;
            else startSearch();
        }
        keys.forceActiveFocus();
    }

    function pick() {
        const i = view.currentIndex;
        if (i < 0 || i >= items.length)
            return;
        close();
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/wallhaven-wallpaper.sh", items[i].url]);
    }

    width: columns * cell + (columns - 1) * gap + 2 * gap
    height: barH + lines * cell + (lines - 1) * gap + 2 * gap
    radius: 0
    color: wal.adapter.special.background
    Behavior on color { ColorAnimation { duration: 400 } }

    MouseArea { anchors.fill: parent }  // keep clicks inside from closing
    HoverHandler { id: hover }

    FileView {
        id: wal
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        adapter: JsonAdapter {
            property JsonObject special: JsonObject { property string background: "#101114" }
        }
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: {
            if (fetch.running) {
                fetch.running = false;  // stop the stale search; onExited starts the new one
            } else {
                root.startSearch();
            }
        }
    }

    Process {
        id: fetch
        onExited: if (root.wanted !== root.runQuery) root.startSearch()
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.wanted !== root.runQuery)
                    return;  // stale: the text changed while it ran
                root.items = root.parse(text);
                root.hasMore = root.items.length >= root.pageSize;
                root.status = root.items.length ? "" : "No results";
                view.currentIndex = 0;
                view.positionViewAtBeginning();
            }
        }
    }

    Process {
        id: more
        property int page: 2
        property string query: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (more.query !== root.runQuery || root.wanted !== root.runQuery)
                    return;  // stale
                const got = root.parse(text);
                const seen = new Set(root.items.map(i => i.id));
                const idx = view.currentIndex, top = view.contentY;
                root.items = root.items.concat(got.filter(i => !seen.has(i.id)));
                view.currentIndex = idx;  // a new model resets the view: put it back
                view.contentY = top;
                root.page = more.page;
                root.hasMore = got.length >= root.pageSize;
                root.maybeMore();
            }
        }
    }

    Rectangle {
        id: tag
        anchors { left: parent.left; leftMargin: 10; top: parent.top; topMargin: 9 }
        width: label.width + 20
        height: 34
        radius: 5
        color: "#E6E6E6"
        Text {
            id: label
            anchors.centerIn: parent
            text: "WALLHAVEN"
            color: "#000000"
            font { family: root.font; pointSize: 12 }
        }
    }

    TextInput {
        id: entry
        anchors { left: tag.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: tag.verticalCenter }
        color: "#ECEFF4"
        font { family: root.font; pointSize: 12 }
        clip: true

        Text {
            visible: !entry.text
            text: "Search wallhaven (1920x1080+)"
            color: "#777777"
            font: entry.font
        }

        onTextEdited: root.typed()
        Keys.onEscapePressed: root.close()
        // Enter / Down / Tab: leave the search box and choose a tile
        Keys.onReturnPressed: root.toTiles()
        Keys.onEnterPressed: root.toTiles()
        Keys.onDownPressed: root.toTiles()
        Keys.onTabPressed: root.toTiles()
    }

    // tile selection: arrows move, Enter picks, Up from the top row or typing returns to the search box
    Item {
        id: keys
        anchors.fill: parent
        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.pick()
        Keys.onEnterPressed: root.pick()
        Keys.onTabPressed: view.currentIndex = Math.min(view.currentIndex + 1, view.count - 1)
        Keys.onBacktabPressed: view.currentIndex = Math.max(view.currentIndex - 1, 0)
        Keys.onPressed: ev => {
            const page = root.lines * root.columns;
            if (ev.key === Qt.Key_Left) view.moveCurrentIndexLeft();
            else if (ev.key === Qt.Key_Right) view.moveCurrentIndexRight();
            else if (ev.key === Qt.Key_Up) {
                if (view.currentIndex < root.columns) entry.forceActiveFocus();
                else view.moveCurrentIndexUp();
            }
            else if (ev.key === Qt.Key_Down) view.moveCurrentIndexDown();
            else if (ev.key === Qt.Key_PageDown) view.currentIndex = Math.min(view.currentIndex + page, view.count - 1);
            else if (ev.key === Qt.Key_PageUp) view.currentIndex = Math.max(view.currentIndex - page, 0);
            else if (ev.key === Qt.Key_Backspace) {
                entry.forceActiveFocus();
                entry.text = entry.text.slice(0, -1);
                entry.cursorPosition = entry.text.length;
                root.typed();
            }
            else if (ev.text.length > 0 && ev.text.charCodeAt(0) >= 32) {
                entry.forceActiveFocus();
                entry.text += ev.text;
                entry.cursorPosition = entry.text.length;
                root.typed();
            }
            else return;
            ev.accepted = true;
        }
    }

    Text {
        visible: root.status !== ""
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: root.barH + (root.lines * root.cell) / 2 - 10 }
        text: root.status
        color: "#777777"
        font { family: root.font; pointSize: 12 }
    }

    GridView {
        id: view
        x: root.gap; y: root.barH + root.gap
        width: root.columns * (root.cell + root.gap)
        height: root.lines * (root.cell + root.gap)
        cellWidth: root.cell + root.gap
        cellHeight: root.cell + root.gap
        clip: true
        interactive: false
        highlightMoveDuration: 0
        model: root.items
        onCurrentIndexChanged: root.maybeMore()

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

            Rectangle {
                anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                width: resText.width + 8; height: resText.height + 2
                color: "#99000000"
                Text {
                    id: resText
                    anchors.centerIn: parent
                    text: tile.modelData.res
                    color: "white"
                    font { family: root.font; pointSize: 8 }
                }
            }

            MenuHint {
                anchors.fill: parent
                hoverEnabled: true
                Accessible.role: Accessible.Button
                Accessible.name: "wallpaper " + tile.modelData.id + " " + tile.modelData.res
                Accessible.onPressAction: clicked(null)
                cursorShape: Qt.PointingHandCursor
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
