import QtQuick

// A pill button the hint overlay (SUPER+D) and screen readers can reach.
// `popup` is the window it sits in (see HintArea).
Rectangle {
    id: btn

    property var popup: null
    property string label: ""
    property bool primary: false
    property bool danger: false
    signal activated

    height: 34
    width: btnText.implicitWidth + 28
    radius: height / 2
    color: primary ? (btnMa.containsMouse ? Theme.mix(Theme.c("flow-4"), Theme.ink, 0.15) : Theme.c("flow-4"))
         : danger ? Theme.alpha(Theme.c("flow-12"), btnMa.containsMouse ? 0.4 : 0.2)
         : Theme.tint(btnMa.containsMouse ? 0.14 : 0.07)

    Text {
        id: btnText
        anchors.centerIn: parent
        text: btn.label
        color: btn.primary ? Theme.c("base") : Theme.c("text")
        font { family: Theme.font; pixelSize: 12; bold: btn.primary }
    }

    HintArea {
        id: btnMa
        popup: btn.popup
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
        Accessible.role: Accessible.Button
        Accessible.name: btn.label
        Accessible.onPressAction: btn.activated()
    }
}
