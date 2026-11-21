import QtQuick
import Quickshell
import Quickshell.Io
import "Calc.js" as Calc
import ".."

// SUPER-tap icon grid, a port of ~/.config/hypr/rofi-app-icon-grid.rosi.
// Moved here from ~/.config/quickshell/launcher/shell.qml unchanged in look.
Rectangle {
    id: root

    required property var apps  // Apps.qml
    readonly property string font: "JetBrainsMono Nerd Font"
    property string query: ""

    // calculator: a typed expression like 2*(3+4) shows its result; Enter copies it
    readonly property var calc: Calc.evaluate(query.startsWith("=") ? query.slice(1) : query)

    // command line: a query starting with ";" runs the rest as a shell command on Enter
    readonly property bool cmdMode: query.startsWith(";")
    readonly property string cmd: query.slice(1).trim()

    Process {
        id: copier
        property string text: ""
        command: ["wl-copy", "--", text]
    }

    // ";" autocomplete: first word from commands in PATH, later words from files (bash compgen)
    property var suggestions: []
    property int sugIndex: -1
    property string sugBase: ""  // query text before the word being completed

    function complete() {
        suggestions = [];
        sugIndex = -1;
        if (!cmdMode)
            return;
        const m = query.match(/^(.*?)(\S*)$/);
        let base = m[1], word = m[2];
        if (word.startsWith(";") && !base) {
            base = ";";
            word = word.slice(1);
        }
        if (!word && !/\s/.test(query.slice(1)))
            return;  // nothing typed yet: do not list every command
        sugBase = base;
        completer.word = word;
        completer.first = !/\s/.test(query.slice(1));
        completeTimer.restart();
    }

    function applySuggestion(i) {
        sugIndex = i;
        query = sugBase + suggestions[i];
        entry.text = query;
        entry.cursorPosition = query.length;
    }

    Timer {
        id: completeTimer
        interval: 60
        onTriggered: {
            completer.running = false;
            completer.running = true;
        }
    }

    Process {
        id: completer
        property string word: ""
        property bool first: true
        command: ["bash", "-c",
            'source ~/.bashrc >/dev/null 2>&1; cd ~; w=${1#;}; if [ "$2" = 1 ]; then compgen -c -- "$w"; else compgen -f -- "$w" | while IFS= read -r f; do [ -d "${f/#\~/$HOME}" ] && echo "$f/" || echo "$f"; done; fi | sort -u | head -8',
            "x", word, first ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.cmdMode)
                    return;
                root.suggestions = text.split("\n").filter(l => l);
                root.sugIndex = -1;
            }
        }
    }

    signal close

    // every word must appear in the name, generic name or keywords (rofi "normal" matching)
    readonly property var matches: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        return apps.apps.filter(e => {
            const hay = [e.name, e.genericName, ...e.keywords].join(" ").toLowerCase();
            return words.every(w => hay.includes(w));
        });
    }

    function open() {
        query = "";
        entry.text = "";  // applySuggestion broke the text binding, so clear it directly
        suggestions = [];
        sugIndex = -1;
        grid.currentIndex = 0;
        entry.forceActiveFocus();
    }

    function accept() {
        if (cmdMode) {
            if (cmd)
                Quickshell.execDetached(["bash", "-c", 'shopt -s expand_aliases; source ~/.bashrc >/dev/null 2>&1; eval "$1"', "x", cmd]);
            close();
        } else if (calc.ok) {
            copier.text = calc.text;
            copier.running = true;
            close();
        } else {
            launch(matches[grid.currentIndex]);
        }
    }

    function launch(entry) {
        if (!entry)
            return;
        apps.launch(entry);
        close();
    }

    width: 682
    height: box.implicitHeight + 36
    radius: 20
    color: Theme.sw("#F2262626")
    border { width: 2; color: Theme.sw("#4D4D4D") }

    MouseArea { anchors.fill: parent }  // keep clicks inside from closing

    Column {
        id: box
        x: 18; y: 18
        width: parent.width - 36
        spacing: 14

        Rectangle {
            width: parent.width
            height: 46
            radius: 6
            color: Theme.sw("#3A3A3A")
            border { width: 2; color: Theme.sw("#5A5A5A") }

            Rectangle {
                id: prompt
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: label.implicitWidth + 20
                height: label.implicitHeight + 10
                radius: 5
                color: Theme.sw("#E6E6E6")
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: "ICONS"
                    color: Theme.sw("#000000")
                    font { family: root.font; pointSize: 12 }
                }
            }

            TextInput {
                id: entry
                anchors { left: prompt.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: root.query
                onTextEdited: { root.query = text; grid.currentIndex = 0; root.complete(); }
                color: Theme.sw("#ECEFF4")
                font { family: root.font; pointSize: 12 }
                clip: true

                Text {
                    visible: !entry.text
                    text: "Search applications  (; command, = calculator)"
                    color: Theme.sw("#777777")
                    font: entry.font
                }

                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
                Keys.onLeftPressed: grid.moveCurrentIndexLeft()
                Keys.onRightPressed: grid.moveCurrentIndexRight()
                Keys.onUpPressed: root.cmdMode && root.suggestions.length
                    ? root.applySuggestion((Math.max(root.sugIndex, 0) + root.suggestions.length - 1) % root.suggestions.length)
                    : grid.moveCurrentIndexUp()
                Keys.onDownPressed: root.cmdMode && root.suggestions.length
                    ? root.applySuggestion((root.sugIndex + 1) % root.suggestions.length)
                    : grid.moveCurrentIndexDown()
                Keys.onTabPressed: root.cmdMode && root.suggestions.length
                    ? root.applySuggestion((root.sugIndex + 1) % root.suggestions.length)
                    : grid.moveCurrentIndexRight()
            }
        }

        // calculator result, shown only while the query is a valid expression
        Rectangle {
            visible: root.calc.ok
            width: parent.width
            height: visible ? 46 : 0
            radius: 6
            color: Theme.sw("#E6E6E6")
            Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: "= " + root.calc.text
                color: Theme.sw("#000000")
                font { family: root.font; pointSize: 14; bold: true }
            }
            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: "Enter copies"
                color: Theme.sw("#444444")
                font { family: root.font; pointSize: 10 }
            }
        }

        // command mode body: same height as the icon grid, so the input field never moves
        Item {
            visible: root.cmdMode
            width: parent.width
            height: visible ? grid.height : 0
            // command line row, shown while the query starts with ";"
            Rectangle {
                width: parent.width
                height: 46
                radius: 6
                color: Theme.sw("#E6E6E6")
                Text {
                    anchors { left: parent.left; leftMargin: 16; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "$ " + root.cmd
                    elide: Text.ElideRight
                    color: Theme.sw("#000000")
                    font { family: root.font; pointSize: 14; bold: true }
                }
                Text {
                    id: hint
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "Enter runs"
                    color: Theme.sw("#444444")
                    font { family: root.font; pointSize: 10 }
                }
            }

            // autocomplete choices; Tab / Down / Up pick one
            Column {
                y: 46 + 14
                visible: root.suggestions.length > 0
                width: parent.width
                spacing: 2
                Repeater {
                    model: root.cmdMode ? root.suggestions : []
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: parent.width
                        height: 30
                        radius: 5
                        color: index === root.sugIndex ? Theme.sw("#5A5A5A") : Theme.sw("#303030")
                        Text {
                            anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: modelData
                            elide: Text.ElideRight
                            color: Theme.sw("#ECEFF4")
                            font { family: root.font; pointSize: 11 }
                        }
                    }
                }
            }
        }

        // 6 x 4 grid of icons, scrolls past that
        GridView {
            id: grid
            visible: !root.cmdMode
            width: parent.width + 12  // the last column's spacing hangs off the edge
            height: cellHeight * 4 - 12  // no trailing gap under the last row
            cellWidth: (parent.width + 12) / 6
            cellHeight: cellWidth
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
                radius: width / 2
                color: selected ? Theme.sw("#5A5A5A") : Theme.sw("#303030")
                border { width: 2; color: selected ? Theme.sw("#E6E6E6") : "transparent" }

                Image {
                    anchors.centerIn: parent
                    width: (parent.width - 8) * 0.9; height: width
                    sourceSize { width: (parent.width - 8) * 0.9; height: width }
                    source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                    asynchronous: true
                }

                MenuHint {
                    anchors.fill: parent
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    Accessible.onPressAction: clicked(null)
                    hoverEnabled: true
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
