import QtQuick
import ".."

// A MouseArea in the full-screen menu overlay that the hint overlay (SUPER+D) should offer.
// The overlay window sits at the screen origin, so no offset. Hidden menus are not visible,
// so BarTargets skips them.
MouseArea {
    id: area

    readonly property bool hintOn: true
    readonly property real hintX: 0
    readonly property real hintY: 0

    Component.onCompleted: BarTargets.add(area)
    Component.onDestruction: BarTargets.remove(area)
}
