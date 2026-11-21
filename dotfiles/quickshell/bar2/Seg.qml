import QtQuick
import "Markup.js" as Markup

// One waybar module: a slice of pill with text, per-side rounding and
// margins, an optional inset bottom line (GTK inset box-shadow) and a tooltip.
Item {
    id: root

    property string text: ""
    property color fg: Theme.c("lavender")
    property color bg: Theme.c("base")
    property real rl: 0          // left corner radius
    property real rr: 0          // right corner radius
    property real padL: 8
    property real padR: 8
    property real mL: 0
    property real mR: 0
    property real fontScale: 1
    property real boxY: 5        // top of the pill inside the 36px bar
    property real boxH: 20
    property bool bold: false
    property color line: "transparent"   // 2px inset line along the bottom
    property string tip: ""
    // CSS "animation: … infinite alternate": blend toward the *B colors and back
    property bool pulse: false
    property int pulseMs: 1000
    property color bgB: bg
    property color lineB: line
    property color fgB: fg
    property real phase: 0
    property var tipper: null
    property bool shown: text !== ""
    property alias hovered: mouse.containsMouse
    default property alias extra: box.data

    signal clicked(int button)
    signal scrolled(bool up)

    visible: shown
    implicitWidth: shown ? mL + box.width + mR : 0
    implicitHeight: 36

    Rectangle {
        id: box
        x: root.mL
        y: root.boxY
        height: root.boxH   // 14px text line + 3px above and below
        width: label.implicitWidth + root.padL + root.padR
        color: root.pulse ? Theme.mix(root.bg, root.bgB, root.phase) : root.bg
        Behavior on color {
            enabled: !root.pulse
            ColorAnimation { duration: 300 }
        }
        topLeftRadius: root.rl
        bottomLeftRadius: root.rl
        topRightRadius: root.rr
        bottomRightRadius: root.rr

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            color: root.pulse ? Theme.mix(root.line, root.lineB, root.phase) : root.line
            visible: root.line.a > 0 || (root.pulse && root.lineB.a > 0)
        }

        Text {
            id: label
            x: root.padL
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5
            text: Theme.icons(Markup.spaces(root.text))
            textFormat: Text.RichText
            color: root.pulse ? Theme.mix(root.fg, root.fgB, root.phase) : root.fg
            font.family: Theme.font
            font.pixelSize: Math.round(Theme.fontPx * root.fontScale)
            font.bold: root.bold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: box
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => root.clicked(e.button)
        // A real button on the accessibility bus, so SUPER+D (hint-atspi) gets a field.
        Accessible.role: Accessible.Button
        Accessible.name: label.text.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
        Accessible.ignored: !root.shown
        Accessible.onPressAction: root.clicked(Qt.LeftButton)
        Component.onCompleted: BarTargets.add(mouse)
        Component.onDestruction: BarTargets.remove(mouse)
        onWheel: e => root.scrolled(e.angleDelta.y > 0)
        onContainsMouseChanged: {
            if (!root.tipper) return;
            if (containsMouse && root.tip !== "") root.tipper.show(box, Markup.spaces(root.tip));
            else root.tipper.hide(box);
        }
    }

    onPulseChanged: if (!pulse) phase = 0

    SequentialAnimation on phase {
        running: root.pulse && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: root.pulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: root.pulseMs; easing.type: Easing.InOutSine }
    }

    onTipChanged: if (tipper && mouse.containsMouse) tipper.show(box, Markup.spaces(tip))
}
