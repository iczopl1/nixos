import QtQuick
import QtQuick.Effects
import "Markup.js" as Markup

// Icon-first bar module: the icon is always shown, the label slides out on
// hover or while `open`. Lives inside a capsule; optional status badge dot.
Item {
    id: root

    property string icon: ""
    property string iconSvg: ""      // name in icons/; stroked line icon tinted by fg
    property string iconFont: "Font Awesome 7 Free"
    property real iconFixedW: 0      // text icons: reserve this width so changing glyphs do not move the bar
    property bool iconRich: false    // icon is Pango-derived HTML (already colored)
    property string label: ""        // HTML
    property color fg: Theme.c("overlay2")
    property color bg: "transparent"
    property color fgB: fg
    property color bgB: bg
    property bool pulse: false
    property int pulseMs: 1000
    property real phase: 0
    property bool open: false
    property int pinButton: Qt.LeftButton   // which button toggles the pin
    property bool pinnable: false    // left click keeps the label open; the old left action moves to middle click
    property string pinKey: ""      // set: the pinned state is saved across restarts
    property bool localPin: false
    readonly property bool pinned: pinKey !== "" ? Pins.map[pinKey] === true : localPin
    property color badge: "transparent"
    property string tip: ""
    property var tipper: null
    property bool shown: icon !== "" || iconSvg !== ""
    readonly property real iconW: iconSvg !== "" ? 14 : iconFixedW > 0 ? iconFixedW : glyph.implicitWidth
    property alias hovered: mouse.containsMouse
    readonly property bool expanded: label !== "" && (open || pinned || mouse.containsMouse)
    property real reveal: expanded ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    signal clicked(int button)
    signal scrolled(bool up)

    visible: shown
    implicitWidth: shown ? body.width : 0
    implicitHeight: 18

    Rectangle {
        id: body
        anchors.verticalCenter: parent.verticalCenter
        height: 18
        radius: 9
        clip: true
        width: 12 + root.iconW + root.reveal * (5 + text.implicitWidth)
        color: root.pulse ? Theme.mix(root.bg, root.bgB, root.phase) : root.bg

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.1)
            opacity: mouse.containsMouse ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }
        }

        Image {
            id: svgIcon
            visible: root.iconSvg !== ""
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            source: root.iconSvg !== "" ? Qt.resolvedUrl("icons/" + root.iconSvg + ".svg") : ""
            sourceSize: Qt.size(56, 56)
            layer.enabled: visible
            layer.effect: MultiEffect {
                colorization: 1.0
                brightness: 1.0
                colorizationColor: root.pulse ? Theme.mix(root.fg, root.fgB, root.phase) : root.fg
            }
        }

        Text {
            id: glyph
            visible: root.iconSvg === ""
            x: 6 + (root.iconFixedW > 0 ? (root.iconFixedW - glyph.implicitWidth) / 2 : 0)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5
            text: root.iconRich ? Theme.icons(root.icon) : root.icon
            textFormat: root.iconRich ? Text.RichText : Text.PlainText
            color: root.pulse ? Theme.mix(root.fg, root.fgB, root.phase) : root.fg
            font.family: root.iconRich ? Theme.font : root.iconFont
            font.weight: root.iconRich ? Font.Normal : Font.Black
            font.pixelSize: Theme.fontPx
        }

        Text {
            id: text
            x: 6 + root.iconW + 5
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5
            opacity: root.reveal
            text: Theme.icons(Markup.spaces(root.label))
            textFormat: Text.RichText
            color: Theme.c("text")
            font.family: Theme.font
            font.pixelSize: Theme.fontPx
        }

        Rectangle {
            visible: root.badge.a > 0
            x: 6 + root.iconW - 3
            y: 11
            width: 6
            height: 6
            radius: 3
            color: root.badge
            border.width: 1.5
            border.color: Theme.c("base")
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: body
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => {
            if (root.pinnable && e.button === root.pinButton) {
                if (root.pinKey !== "") Pins.set(root.pinKey, !root.pinned);
                else root.localPin = !root.localPin;
            }
            else root.clicked(e.button);
        }
        Accessible.role: Accessible.Button
        Accessible.name: (root.tip || root.label || root.icon).replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
        Accessible.ignored: !root.shown
        Accessible.onPressAction: root.clicked(Qt.LeftButton)
        Component.onCompleted: BarTargets.add(mouse)
        Component.onDestruction: BarTargets.remove(mouse)
        onWheel: e => root.scrolled(e.angleDelta.y > 0)
        onContainsMouseChanged: {
            if (!root.tipper) return;
            if (containsMouse && root.tip !== "") root.tipper.show(body, Markup.spaces(root.tip));
            else root.tipper.hide(body);
        }
    }

    onPulseChanged: if (!pulse) phase = 0

    SequentialAnimation on phase {
        running: root.pulse && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: root.pulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: root.pulseMs; easing.type: Easing.InOutSine }
    }

    onTipChanged: if (tipper && mouse.containsMouse) tipper.show(body, Markup.spaces(tip))
}
