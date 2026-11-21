import QtQuick
import QtQuick.Effects
import ".."

// A rofi -dmenu look-alike: prompt + search bar over a grid of elements, styled
// from one ~/.config/hypr/rofi-*.rosi theme (window, inputbar, listview, element).
// items: [{ text, icon?, meta? }]; meta is searched but not shown, like rofi's meta.
Rectangle {
    id: box

    // .rosi colors
    property color bg
    property color panel
    property color panelStrong
    property color borderColor
    property color borderSoft
    property color textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"
    property color textFaint
    property color accent
    property color selText

    property string prompt: ""
    property string placeholder: ""
    property bool showInput: true
    property string fontFamily: "JetBrains Mono"
    property real fontPt: 12
    property string itemFamily: fontFamily
    property real itemPt: fontPt
    property bool rich: false  // item text is StyledText
    // Font Awesome glyphs in plain text: Qt won't fall back to an icon font for them
    // like pango does, so each one is wrapped in Font Awesome (fc-match would pick
    // Arial for some, which draws nothing)
    property bool glyphs: false
    property bool centerText: false

    readonly property var brands: ["", "", ""]  // windows, bluetooth, bluetooth-b
    function glyphText(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;")
            .replace(/[-]/g, ch => brands.includes(ch)
                ? "<span style=\"font-family:'Font Awesome 7 Brands'\">" + ch + "</span>"
                : "<span style=\"font-family:'Font Awesome 7 Free';font-weight:900\">" + ch + "</span>");
    }

    // listview / element
    property int columns: 1
    property int lines: 10
    property bool dynamic: true  // shrink to the rows in use
    property int spacing: 10
    property int elemRadius: 20
    property int padV: 12
    property int padH: 14
    property int elemSpacing: 14
    property int elemBorder: 0
    property int iconSize: 0
    property int iconRadius: 0
    property bool iconOnly: false
    property bool iconCache: true

    property var items: []
    property string query: ""
    // every word must appear in text or meta (rofi -i -matching normal)
    readonly property var matches: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        if (!words.length)
            return items;
        return items.filter(i => {
            const hay = (i.text + " " + (i.meta || "")).toLowerCase();
            return words.every(w => hay.includes(w));
        });
    }

    signal picked(var item, int index)
    signal cancelled

    // call when shown: clears the search and takes the keyboard
    property var lastPointer: null  // global pointer position seen since opening

    function reset() {
        lastPointer = null;
        query = "";
        view.currentIndex = 0;
        view.positionViewAtBeginning();
        entry.forceActiveFocus();
    }

    width: 840
    height: col.implicitHeight + 36
    radius: 26
    color: bg
    border { width: 2; color: borderSoft }

    MouseArea { anchors.fill: parent }  // keep clicks inside from closing

    FontMetrics {
        id: fm
        font.family: box.itemFamily
        font.pointSize: box.itemPt
    }
    // icon-only tiles are square: the icon takes the column width, so the gap
    // around it is the same on every side (set padV = padH)
    readonly property int iconSide: iconOnly
        ? Math.floor((width - 36 + spacing) / columns - spacing - 2 * (padH + elemBorder))
        : iconSize
    readonly property int elemH: Math.max(iconSide, Math.ceil(fm.height)) + 2 * (padV + elemBorder)

    function pick() {
        const i = view.currentIndex;
        if (i >= 0 && i < matches.length)
            picked(matches[i], items.indexOf(matches[i]));
    }

    Column {
        id: col
        x: 18; y: 18
        width: parent.width - 36
        spacing: box.showInput ? 14 : 0

        // no inputbar in the theme: keep the entry (typing still filters), just hidden
        Rectangle {
            width: parent.width
            height: box.showInput ? 46 : 0
            opacity: box.showInput ? 1 : 0
            radius: 18
            color: box.panel
            border { width: 2; color: box.borderColor }

            Rectangle {
                id: promptPill
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: box.prompt !== ""
                width: visible ? promptText.implicitWidth + 20 : 0
                height: promptText.implicitHeight + 10
                radius: height / 2
                color: box.accent
                Text {
                    id: promptText
                    anchors.centerIn: parent
                    text: box.prompt
                    color: box.selText
                    font { family: box.fontFamily; pointSize: box.fontPt }
                }
            }

            TextInput {
                id: entry
                anchors { left: promptPill.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: box.query
                onTextEdited: { box.query = text; view.currentIndex = 0; }
                color: box.textColor
                font { family: box.fontFamily; pointSize: box.fontPt }
                clip: true

                Text {
                    visible: !entry.text
                    text: box.placeholder
                    color: box.textFaint
                    font: entry.font
                }

                Keys.onEscapePressed: box.cancelled()
                Keys.onReturnPressed: box.pick()
                Keys.onEnterPressed: box.pick()
                Keys.onUpPressed: view.moveCurrentIndexUp()
                Keys.onDownPressed: view.moveCurrentIndexDown()
                Keys.onTabPressed: view.currentIndex = Math.min(view.currentIndex + 1, view.count - 1)
                Keys.onBacktabPressed: view.currentIndex = Math.max(view.currentIndex - 1, 0)
                Keys.onPressed: ev => {
                    const page = box.lines * box.columns;
                    if (box.columns > 1 && ev.key === Qt.Key_Left) view.moveCurrentIndexLeft();
                    else if (box.columns > 1 && ev.key === Qt.Key_Right) view.moveCurrentIndexRight();
                    else if (ev.key === Qt.Key_PageDown) view.currentIndex = Math.min(view.currentIndex + page, view.count - 1);
                    else if (ev.key === Qt.Key_PageUp) view.currentIndex = Math.max(view.currentIndex - page, 0);
                    else return;
                    ev.accepted = true;
                }
            }
        }

        GridView {
            id: view
            width: parent.width + box.spacing  // the last column's spacing hangs off the edge
            readonly property int rows: box.dynamic ? Math.min(box.lines, Math.ceil(count / box.columns)) : box.lines
            height: rows * cellHeight - box.spacing
            cellWidth: width / box.columns
            cellHeight: box.elemH + box.spacing
            clip: true
            interactive: false
            highlightMoveDuration: 0
            model: box.matches
            // a refresh (clipboard previews, bluetooth/pipewire changes) keeps the selection;
            // typing and reset() send it back to the top themselves
            onModelChanged: currentIndex = Math.max(0, Math.min(currentIndex, count - 1))

            delegate: Rectangle {
                id: elem
                required property var modelData
                required property int index
                readonly property bool selected: GridView.isCurrentItem
                width: view.cellWidth - box.spacing
                height: box.elemH
                radius: box.elemRadius
                color: selected ? box.panelStrong : box.panel
                border { width: box.elemBorder; color: selected ? box.accent : "transparent" }

                Image {
                    id: icon
                    visible: box.iconSize > 0 && !!elem.modelData.icon && box.iconRadius === 0
                    x: box.iconOnly ? (parent.width - width) / 2 : box.padH
                    anchors.verticalCenter: parent.verticalCenter
                    width: box.iconSize > 0 && elem.modelData.icon ? box.iconSide : 0
                    height: box.iconSide
                    sourceSize { width: icon.width; height: icon.height }
                    fillMode: Image.PreserveAspectCrop
                    source: box.iconSize > 0 && elem.modelData.icon ? elem.modelData.icon : ""
                    asynchronous: true
                    cache: box.iconCache
                }

                // rounded icon corners (element-icon border-radius)
                Rectangle {
                    id: iconMask
                    visible: false
                    layer.enabled: box.iconRadius > 0
                    width: icon.width; height: icon.height
                    radius: box.iconRadius
                }
                MultiEffect {
                    visible: box.iconRadius > 0 && icon.width > 0
                    anchors.fill: icon
                    source: icon
                    maskEnabled: true
                    maskSource: iconMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Text {
                    visible: !box.iconOnly
                    anchors {
                        left: icon.width > 0 ? icon.right : parent.left
                        right: parent.right
                        leftMargin: icon.width > 0 ? box.elemSpacing : box.padH
                        rightMargin: box.padH
                        verticalCenter: parent.verticalCenter
                    }
                    text: box.glyphs ? box.glyphText(elem.modelData.text) : elem.modelData.text
                    textFormat: box.glyphs ? Text.RichText : box.rich ? Text.StyledText : Text.PlainText
                    elide: Text.ElideRight  // not for RichText: clip instead
                    clip: box.glyphs
                    maximumLineCount: 1
                    horizontalAlignment: box.centerText ? Text.AlignHCenter : Text.AlignLeft
                    color: elem.selected ? box.selText : box.textColor
                    font { family: box.itemFamily; pointSize: box.itemPt }
                }

                MenuHint {
                    anchors.fill: parent
                    hoverEnabled: true
                    Accessible.role: Accessible.Button
                    Accessible.name: String(elem.modelData.text).replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
                    Accessible.onPressAction: clicked(null)
                    cursorShape: Qt.PointingHandCursor
                    // select on real pointer motion only: not when the box opens or
                    // scrolls under a resting pointer (that would steal the keyboard pick)
                    onPositionChanged: mouse => {
                        const g = mapToGlobal(mouse.x, mouse.y);
                        const last = box.lastPointer;
                        box.lastPointer = g;
                        if (last && (last.x !== g.x || last.y !== g.y))
                            view.currentIndex = elem.index;
                    }
                    onClicked: { view.currentIndex = elem.index; box.pick(); }
                }
            }

            WheelHandler {
                onWheel: ev => ev.angleDelta.y < 0 ? view.moveCurrentIndexDown() : view.moveCurrentIndexUp()
            }
        }
    }
}
