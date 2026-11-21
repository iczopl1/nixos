import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notification daemon inside the bar (was a separate `mako` process).
// Port of ~/.config/mako/config: same colors, sizes and timeouts, same
// per-app / per-category cards (tailnet, clev.done, Claude Code), newest on top.
// Left click: run the "default" action and close. Right click: close.
Scope {
    id: root

    signal shown()   // a card is about to appear (dropped notifications never fire this)

    // mako colors are #RRGGBBAA; QML wants #AARRGGBB
    function col(s) {
        return s.length === 9 ? "#" + s.slice(7) + s.slice(1, 7) : s;
    }

    readonly property var base: ({
        bg: "#1a1538E6", fg: "#dad1deFF", border: "#AAA8CAFF", bw: 1, radius: 10,
        width: 360, maxh: 110, pad: 12, fsize: 10, timeout: 5, progress: "#787DB6FF",
        sumColor: "", sumBold: false, sumLarge: false, sumPrefix: ""
    })

    // Light desktop: invert the card background and text, darken the accent colors.
    // Colors here are #RRGGBBAA, so the alpha stays last.
    function lite(s) {
        if (!Theme.isLight) return s;
        const ch = (c, f) => c.length !== 9 ? c : "#" + [1, 3, 5].map(i => f(parseInt(c.substr(i, 2), 16)).toString(16).padStart(2, "0")).join("") + c.slice(7);
        const inv = c => ch(c, v => 255 - v), dim = c => ch(c, v => Math.round(v * 0.6));
        s.bg = inv(s.bg); s.fg = inv(s.fg);
        s.border = dim(s.border); s.progress = dim(s.progress);
        if (s.sumColor) s.sumColor = dim(s.sumColor);
        return s;
    }

    // layered like mako sections: base < urgency < app/category (later wins)
    function style(n) {
        let s = Object.assign({}, base);
        const u = n.urgency;
        if (u === NotificationUrgency.Low)
            Object.assign(s, { bg: "#1a1538D9", fg: "#dad1deCC", border: "#926AA7FF", timeout: 3 });
        else if (u === NotificationUrgency.Critical)
            Object.assign(s, { bg: "#442222FF", fg: "#F7F1FAFF", border: "#ff9999FF", bw: 2, timeout: 0 });
        const cat = n.hints && n.hints["category"] ? String(n.hints["category"]) : "";
        const card = { width: 560, maxh: 1000, bw: 2, radius: 18, pad: 16, fsize: 11, sumBold: true, sumLarge: true, sumPrefix: "✦ " };
        if (n.appName === "tailnet")
            Object.assign(s, { width: 600, maxh: 400, timeout: 10 });
        if (n.appName === "clev" && cat === "clev.done")
            Object.assign(s, card, { bg: "#2f3434f2", fg: "#ffffffff", border: "#88ffa8ff", progress: "#8F9C63FF", sumColor: "#8fd5baff" });
        if (n.appName === "Claude Code" && cat === "claude-code") {
            Object.assign(s, card, { timeout: 10, bg: "#352e1cf2", fg: "#ffffffff", border: "#ffd24aff", progress: "#e0a82eFF", sumColor: "#ffd24aff" });
            if (u === NotificationUrgency.Low)
                Object.assign(s, { timeout: 6, bg: "#34261af2", border: "#ff9a3cff", sumColor: "#ff9a3cff" });
            else if (u === NotificationUrgency.Critical)
                Object.assign(s, { bg: "#381e1af2", border: "#ff4a3aff", bw: 3, timeout: 0, sumColor: "#ff5a44ff" });
        }
        return lite(s);
    }

    NotificationServer {
        id: server
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        keepOnReload: false
        // blueman's popups (summary = device name, body = Connected / Disconnected): the bluetooth chip already shows these events
        onNotification: n => {
            if (n.appName.toLowerCase() === "blueman" && /\b(dis)?connected\b/i.test(n.body)) return;
            n.tracked = true;
            root.shown();
        }
    }

    // widest card on screen, so the click-through mask hugs the cards
    readonly property real maxWidth: server.trackedNotifications.values.reduce((w, n) => Math.max(w, style(n).width), 0)

    PanelWindow {
        id: win
        visible: server.trackedNotifications.values.length > 0
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: 38; right: 4 }   // bar is 22px (3 + 19 zone): stay below it, never cover it
        implicitWidth: stack.width
        implicitHeight: stack.height
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: stack }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-notifications"

        // The model is the server's own list, so delegates (and their timeouts) are
        // stable. BottomToTop puts the newest notification on top, like mako.
        ListView {
            id: stack
            width: root.maxWidth
            height: contentHeight
            interactive: false
            spacing: 10
            verticalLayoutDirection: ListView.BottomToTop
            model: server.trackedNotifications

            delegate: Item {
                id: slot
                required property var modelData
                x: stack.width - width   // right-align narrower cards
                width: card.width
                height: card.height

                Rectangle {
                    id: card
                    readonly property var n: slot.modelData
                    readonly property var st: root.style(n)
                    readonly property string iconSrc: n.image !== "" ? n.image
                        : n.appIcon !== "" ? (n.appIcon.startsWith("/") ? n.appIcon : Quickshell.iconPath(n.appIcon, true)) : ""
                    readonly property var prog: n.hints && n.hints["value"] !== undefined ? Number(n.hints["value"]) : -1
                    readonly property var acts: (n.actions || []).filter(a => a.identifier !== "default")

                    width: st.width
                    height: Math.min(st.maxh, content.implicitHeight + st.pad * 2)
                    radius: st.radius
                    color: root.col(st.bg)
                    border.color: root.col(st.border)
                    border.width: st.bw
                    clip: true

                    Timer {
                        // app timeout is in ms: -1 = use the style's default, 0 = stay until closed
                        readonly property int ms: card.n.expireTimeout > 0 ? card.n.expireTimeout
                            : card.n.expireTimeout === 0 ? 0 : card.st.timeout * 1000
                        interval: ms
                        running: ms > 0
                        onTriggered: card.n.expire()
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: ev => {
                            if (ev.button === Qt.LeftButton) {
                                const d = (card.n.actions || []).find(a => a.identifier === "default");
                                if (d) d.invoke();
                            }
                            card.n.dismiss();
                        }
                    }

                    Rectangle {   // progress bar along the bottom
                        visible: card.prog >= 0
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        height: 4
                        width: parent.width * Math.max(0, Math.min(100, card.prog)) / 100
                        color: root.col(card.st.progress)
                    }

                    Row {
                        id: content
                        x: card.st.pad
                        y: card.st.pad
                        width: card.width - card.st.pad * 2
                        spacing: 10

                        Image {
                            visible: card.iconSrc !== ""
                            source: card.iconSrc
                            width: visible ? 40 : 0
                            height: 40
                            sourceSize: Qt.size(40, 40)
                            fillMode: Image.PreserveAspectFit
                        }

                        Column {
                            width: parent.width - (card.iconSrc !== "" ? 50 : 0)
                            spacing: 4

                            Text {
                                width: parent.width
                                text: card.st.sumPrefix + card.n.summary
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: "Fira Sans"
                                font.pointSize: card.st.fsize * (card.st.sumLarge ? 1.25 : 1)
                                font.bold: card.st.sumBold
                                color: root.col(card.st.sumColor !== "" ? card.st.sumColor : card.st.fg)
                            }

                            Text {
                                visible: card.n.body !== ""
                                width: parent.width
                                text: card.n.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                font.family: "Fira Sans"
                                font.pointSize: card.st.fsize
                                color: root.col(card.st.fg)
                            }

                            Row {
                                visible: card.acts.length > 0
                                spacing: 6
                                Repeater {
                                    model: card.acts
                                    Rectangle {
                                        required property var modelData
                                        width: lbl.implicitWidth + 16
                                        height: lbl.implicitHeight + 8
                                        radius: 6
                                        color: "#33ffffff"
                                        Text {
                                            id: lbl
                                            anchors.centerIn: parent
                                            text: parent.modelData.text
                                            font.family: "Fira Sans"
                                            font.pointSize: card.st.fsize
                                            color: root.col(card.st.fg)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: { parent.modelData.invoke(); card.n.dismiss(); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
