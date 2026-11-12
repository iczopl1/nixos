import QtQuick

// A MouseArea inside a popup window that the hint overlay (SUPER+D) should offer.
// `popup` is the CalendarPopup (or any window object with hintOx / hintOy / visible):
// BarTargets places the box with that offset instead of the bar's own origin.
MouseArea {
    id: area

    property var popup: null
    readonly property bool hintOn: popup ? popup.visible : false
    readonly property real hintX: popup ? popup.hintOx : 0
    readonly property real hintY: popup ? popup.hintOy : 0

    Component.onCompleted: BarTargets.add(area)
    Component.onDestruction: BarTargets.remove(area)
}
