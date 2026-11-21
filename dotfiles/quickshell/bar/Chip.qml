import QtQuick
import QtQuick.Effects
import Quickshell.Io
import "Markup.js" as Markup

// Icon-first bar module: the icon is always shown, the label slides out on
// hover or while `open`. Lives inside a capsule; optional status badge dot.
Item {
    id: root

    property string icon: ""
    property string iconSvg: ""      // name in icons/; stroked line icon tinted by fg
    property string iconFont: "Font Awesome 7 Free"
    property real iconFixedW: 0      // text icons: reserve this width so changing glyphs do not move the bar
    property int iconPx: Theme.fontPx   // glyph size for text/rich icons
    property real iconDy: 0          // nudge the text/rich icon vertically (negative = up)
    property color iconColor: "transparent"   // set: the svg icon is drawn in exactly this color (no brightness normalizing)
    property string sub: ""          // small text at the bottom right of the icon
    property color subColor: Theme.ink
    readonly property real subExtra: 0   // the sub text overlays the icon, it never widens the chip
    property bool iconRich: false    // icon is Pango-derived HTML (already colored)
    property string label: ""        // HTML
    // this chip's color from the flow gradient, by its x position on the screen
    property real sx: 0
    readonly property color flowFg: Theme.flowAt((sx + BarTargets.origin.x + width / 2) / BarTargets.screenW)
    function updateSx() { if (visible) sx = mapToItem(null, 0, 0).x; }
    onXChanged: updateSx()
    onWidthChanged: updateSx()
    onVisibleChanged: { updateSx(); paintReady = false; if (visible) paintTimer.restart(); }
    Component.onCompleted: { updateSx(); if (visible) paintTimer.restart(); }
    Timer { interval: 400; running: root.visible; repeat: true; onTriggered: root.updateSx() }
    property color fg: Theme.c("overlay2")
    // what is actually drawn: fg/fgB pulled to the gradient's average brightness, so every chip is equally bright
    readonly property real tgt: Theme.flowTarget()
    property bool keepColor: false   // skip brightness/white normalizing (alert colors)
    readonly property color fgN: keepColor ? fg : Theme.normalize(fg, tgt)
    readonly property color fgBN: keepColor ? fgB : Theme.normalize(fgB, tgt)
    property color bg: "transparent"
    property color fgB: fg
    property color bgB: bg
    property bool bob: false          // icon and label bob up and down
    readonly property real bobY: bobbing ? -2 * Math.sin(bobPhase) : 0
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
    property string prefix: ""        // always-visible text left of the icon (e.g. feels-like temperature)
    readonly property real pad: prefix !== "" ? prefixText.implicitWidth + 4 : 0
    property bool shown: icon !== "" || iconSvg !== ""
    readonly property real iconW: iconSvg !== "" ? 14 : iconFixedW > 0 ? iconFixedW : Math.max(14, glyph.implicitWidth)
    property alias hovered: mouse.containsMouse
    readonly property bool expanded: label !== "" && (open || pinned || mouse.containsMouse)
    property real reveal: expanded ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    // labelFade: a changed label fades/slides out and the new one in, and the
    // width eases instead of jumping (for labels that change often, e.g. lyrics)
    property bool labelFade: false
    property string shownLabel: label
    property real labelOp: 1
    property real labelDy: 0
    function swapLabel() {
        if (!labelFade || label === shownLabel) return;
        if (labelSwap.running) return;   // it picks up the newest label when it swaps
        // closed, or the same line growing word by word: no fade, the width eases
        if (reveal <= 0 || (shownLabel !== "" && label.indexOf(shownLabel) === 0)) {
            shownLabel = label;
            return;
        }
        labelSwap.start();
    }
    SequentialAnimation {
        id: labelSwap
        ParallelAnimation {
            NumberAnimation { target: root; property: "labelOp"; to: 0; duration: 90; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "labelDy"; to: -5; duration: 90; easing.type: Easing.InQuad }
        }
        ScriptAction { script: { root.shownLabel = root.label; root.labelDy = 5; } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "labelOp"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "labelDy"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }
        onFinished: root.swapLabel()   // the label changed again meanwhile
    }
    // maxLabelW > 0: the label is at most this wide. The text is pinned to the
    // label's right end, so longer text shows its end and scrolls left as it grows.
    property real maxLabelW: 0
    // the wave draws each letter on its own, which comes out a bit wider than the plain text
    readonly property real contentW: waving ? Math.max(text.implicitWidth, waveRow.width) : text.implicitWidth
    property real labelW: maxLabelW > 0 ? Math.min(contentW, maxLabelW) : contentW
    Behavior on labelW {
        enabled: root.labelFade
        NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
    }
    // text that only grew at the end starts this far right (out of sight) and
    // glides in. Same timing as labelW, so while the label still widens the
    // text stands still and only the end is revealed.
    property real flowLag: 0
    property string _prevLabel: ""
    property bool _grew: false
    property real _lastW: 0
    onShownLabelChanged: {
        _grew = labelFade && _prevLabel !== "" && shownLabel.indexOf(_prevLabel) === 0;
        _prevLabel = shownLabel;
        if (!_grew) { lagAnim.stop(); flowLag = 0; }
    }
    NumberAnimation {
        id: lagAnim
        target: root; property: "flowLag"; to: 0
        duration: 350; easing.type: Easing.OutCubic
    }
    // plain text for the letter wave: entities decoded; only the tail that can
    // be visible gets a Text item per letter (index offset keeps the wave steady)
    readonly property string wavePlain: shownLabel.replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&amp;/g, "&")
    readonly property int waveCap: maxLabelW > 0 ? Math.ceil(maxLabelW / 4) + 8 : 100000
    readonly property int waveStart: Math.max(0, wavePlain.length - waveCap)

    signal clicked(int button)
    signal scrolled(bool up)

    // ping(): hold the label open for 5 s (use as `open: flashing || ...`)
    property bool flashing: false
    function ping() {
        flashing = true;
        flashTimer.restart();
    }
    Timer {
        id: flashTimer
        interval: 5000
        onTriggered: root.flashing = false
    }

    // bar hidden: unhiding itself (label slides out, or the chip appears) brings its pill up for 6 s
    property bool live: false
    Timer { interval: 4000; running: true; onTriggered: root.live = true }
    function requestPeek() {
        let p = parent;
        while (p && !p.isCap) p = p.parent;
        if (p) p.peek(root);
    }
    onOpenChanged: if (open && live) requestPeek()
    onShownChanged: {
        if (shown && live) requestPeek();
        if (shown) kick();
    }

    // Qt can lose the on-screen drawing of a chip that Cap moved (saved order) while it was
    // hidden or not yet drawn: it takes its slot but shows nothing. Hiding it for a few frames
    // and showing it again redraws it. Cap calls this after moving chips; a chip also does it
    // each time it appears.
    property bool kicking: false
    function kick() {
        if (dragging) return;
        kicking = true;
        kickTimer.restart();
    }
    Timer {
        id: kickTimer
        interval: 100
        onTriggered: root.kicking = false
    }

    // drag to reorder: the pill this chip sits in (its direct parent's Cap)
    property bool dragging: false
    function dragCap() {
        let p = parent;
        while (p && !p.isCap) p = p.parent;
        return p;
    }
    function endDrag() {
        mouse.held = false;
        dragging = false;
        const c = dragCap();
        if (c) c.dragEnd(root);
    }
    opacity: dragging ? 0.5 : 1
    scale: dragging ? 1.1 : 1
    z: dragging ? 5 : 0

    visible: shown && !kicking

    // The tinted icon is a layer. A chip that appears after startup (bluetooth, battery: shown
    // once the adapter / battery is read) got an empty layer, so the icon stayed invisible.
    // Turn the layer on only after the chip has been visible for a moment.
    property bool paintReady: false
    Timer {
        id: paintTimer
        interval: 80
        onTriggered: root.paintReady = true
    }
    implicitWidth: shown ? body.width : 0
    implicitHeight: 18

    Rectangle {
        id: body
        anchors.verticalCenter: parent.verticalCenter
        height: 18
        radius: 9
        transform: [Translate { x: root.shakeX }, Rotation { angle: root.shakeX * 1.5; origin.x: body.width / 2; origin.y: body.height / 2 }]
        clip: true
        width: 12 + root.pad + root.iconW + root.subExtra + root.reveal * (5 + root.labelW)
        color: root.pulse ? Theme.mix(root.bg, root.bgB, root.phase) : root.bg

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.tint(0.1)
            opacity: mouse.containsMouse ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }
        }

        Image {
            id: svgIcon
            visible: root.iconSvg !== ""
            opacity: root.fg.a   // the svg tint ignores alpha, so dim by opacity
            x: 6 + root.pad
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.bobY
            width: 14
            height: 14
            source: root.iconSvg !== "" ? Qt.resolvedUrl("icons/" + root.iconSvg + ".svg") : ""
            sourceSize: Qt.size(56, 56)
            layer.enabled: root.paintReady
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: { if (root.iconColor.a > 0) return root.iconColor; const k = root.pulse ? Theme.mix(root.fgN, root.fgBN, root.phase) : root.fgN; return Qt.rgba(k.r, k.g, k.b, 1); }
            }
        }

        Text {
            id: prefixText
            visible: root.prefix !== ""
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5 + (root.bobWave ? 0 : root.bobY)
            text: root.prefix
            color: root.pulse ? Theme.mix(root.fgN, root.fgBN, root.phase) : root.fgN
            font.family: Theme.font
            font.pixelSize: Theme.fontPx
        }

        Text {
            id: glyph
            visible: root.iconSvg === ""
            x: 6 + root.pad + (root.iconW - glyph.implicitWidth) / 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5 + root.iconDy
            text: root.iconRich ? Theme.icons(root.icon) : root.icon
            textFormat: root.iconRich ? Text.RichText : Text.PlainText
            color: root.pulse ? Theme.mix(root.fgN, root.fgBN, root.phase) : root.fgN
            font.family: root.iconRich ? Theme.font : root.iconFont
            font.weight: root.iconRich ? Font.Normal : Font.Black
            font.pixelSize: root.iconPx
            opacity: root.wxOpacity
            transform: [Translate { x: root.wxDx; y: root.wxDy }, Rotation { angle: root.wxRot; origin.x: glyph.width / 2; origin.y: glyph.height / 2 }, Scale { xScale: root.wxScale; yScale: root.wxScale; origin.x: glyph.width / 2; origin.y: glyph.height / 2 }]
        }

        // thick outline: copies of the number in the background color around it
        Repeater {
            model: root.sub !== "" ? 8 : 0
            Text {
                required property int index
                text: root.sub
                x: subText.x + 2 * Math.cos(index * Math.PI / 4)
                y: subText.y + 2 * Math.sin(index * Math.PI / 4)
                color: Theme.c("base")
                font: subText.font
            }
        }

        Text {
            id: subText
            visible: root.sub !== ""
            text: root.sub
            x: 6 + root.pad + root.iconW + 1 - implicitWidth
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -1
            color: Theme.isLight ? Qt.hsva(root.subColor.hsvHue, Math.min(1, root.subColor.hsvSaturation * 1.1), Math.min(root.subColor.hsvValue, 1) * 0.42, 1) : Qt.hsva(root.subColor.hsvHue, root.subColor.hsvSaturation * 0.6, root.subColor.hsvValue * 0.9, 1)
            font.family: Theme.font
            font.pixelSize: 10
            font.bold: false
            style: Text.Outline
            styleColor: Theme.c("base")
        }

        // the label sits in a window maxLabelW wide; longer text scrolls left so its end shows
        Item {
            id: labelBox
            x: 6 + root.pad + root.iconW + root.subExtra + 5
            width: root.labelW
            height: parent.height
            clip: root.maxLabelW > 0

        Text {
            id: text
            // fits: left aligned. Too long: its end at the right edge (plus the glide-in lag)
            x: root.maxLabelW > 0 ? Math.min(0, root.maxLabelW - implicitWidth + root.flowLag) : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5 + root.labelDy + (root.bobWave ? 0 : root.bobY)
            opacity: root.waving ? 0 : root.reveal * root.labelOp
            text: Theme.icons(Markup.spaces(root.shownLabel))
            textFormat: Text.RichText
            color: root.pulse ? Theme.mix(root.fgN, root.fgBN, root.phase) : root.fgN
            font.family: Theme.font
            font.pixelSize: Theme.fontPx
            onImplicitWidthChanged: {
                const dw = implicitWidth - root._lastW;
                root._lastW = implicitWidth;
                if (root._grew && dw > 0) {
                    root._grew = false;
                    lagAnim.stop();
                    root.flowLag += dw;
                    lagAnim.start();
                }
            }
        }

        // wave mode: each letter bobs with a phase shift, so a sine wave runs through the text
        Row {
            id: waveRow
            visible: root.waving
            x: root.maxLabelW > 0 ? Math.min(0, root.maxLabelW - width + root.flowLag) : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5 + root.labelDy
            opacity: root.reveal * root.labelOp
            Repeater {
                model: root.waving ? root.wavePlain.length - root.waveStart : 0
                Text {
                    required property int index
                    readonly property int at: root.waveStart + index
                    text: root.wavePlain[at]
                    color: root.fgN
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx
                    transform: Translate { y: -2 * Math.sin(root.bobPhase - at * 0.25) }
                }
            }
        }
        }

        // overflowing label: soft fade at its left edge instead of a hard cut
        Rectangle {
            visible: root.maxLabelW > 0 && (root.waving ? waveRow.x : text.x) < -0.5   // only when text is cut on the left
            x: labelBox.x
            width: 16
            height: parent.height
            opacity: root.reveal
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.c("base") }
                GradientStop { position: 1; color: Theme.alpha(Theme.c("base"), 0) }
            }
        }

        // cloudy: two small clouds above the big one that fade in and out in turn (switch: weatherfx)
        Repeater {
            model: root.wxClouds ? 2 : 0
            Text {
                required property int index
                text: "\u2601"
                font.family: root.iconFont
                font.weight: Font.Black
                font.pixelSize: Math.round(root.iconPx * 0.5)
                color: root.fgN
                x: 6 + root.pad + (index === 0 ? -1 : root.iconW - implicitWidth + 1)
                y: index === 0 ? -1 : 1
                opacity: 0.5 + 0.5 * Math.sin(root.wxPhase + index * Math.PI)
            }
        }

        // rain / snow: a few drops fall through the icon (switch: weatherfx)
        Repeater {
            model: root.wxFalling ? 5 : 0
            Rectangle {
                required property int index
                readonly property real p: (root.wxPhase / (Math.PI * 2) * (root.wx === "snow" ? 1 : 2) + index * 0.2) % 1
                visible: root.wxFalling
                width: root.wx === "snow" ? 2 : 1
                height: root.wx === "snow" ? 2 : 3
                radius: root.wx === "snow" ? 1 : 0
                color: root.fgN
                opacity: 0.85 * Math.sin(p * Math.PI)
                x: 6 + root.pad + ((index * 37) % 100) / 100 * (root.iconW - 2) + (root.wx === "snow" ? 2 * Math.sin(root.wxPhase + index) : 0)
                y: -2 + p * 22
                rotation: root.wx === "snow" ? 0 : 15
            }
        }

        Rectangle {
            visible: root.badge.a > 0
            x: 6 + root.pad + root.iconW - 4
            y: 10
            width: 8
            height: 8
            radius: 4
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
        // hold left click, then drag: move this chip (also into the other pill); the order is saved
        pressAndHoldInterval: 300
        property bool held: false
        onPressed: e => { held = false; }
        onPressAndHold: e => {
            if (e.button !== Qt.LeftButton) return;
            const c = root.dragCap();
            if (!c) return;
            held = true;
            root.dragging = true;
            if (root.tipper) root.tipper.hide(body);
            c.dragStart(root);
        }
        onPositionChanged: e => {
            if (!held) return;
            root.dragCap().dragMove(root, mouse.mapToItem(null, e.x, e.y));
        }
        onReleased: e => { if (held) root.endDrag(); }
        onCanceled: if (held) root.endDrag()
        onClicked: e => {
            if (held) return;
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

    // ripple each time the shown value changes (off for chips with their own ripple)
    property bool autoRipple: true
    // switches from power-fx's effects.conf (a line without # = on); on if the file is unreadable
    property bool cfgBar: true
    property bool cfgVol: true
    property bool cfgBob: true
    property bool cfgPhone: true
    property bool cfgWx: true
    FileView {
        id: cfgFile
        path: "/home/iczo/syshelp/power-fx/effects.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = "\n" + cfgFile.text();   // not bare text(): the label Text has id "text"
            root.cfgBar = /\n\s*barripple(\s|$)/.test(t);
            root.cfgVol = /\n\s*volripple(\s|$)/.test(t);
            root.cfgBob = /\n\s*musicbob(\s|$)/.test(t);
            root.cfgPhone = /\n\s*phonefile(\s|$)/.test(t);
            root.cfgWx = /\n\s*weatherfx(\s|$)/.test(t);
        }
    }
    property bool rippleReady: false
    property real arp: 1
    Timer { interval: 2500; running: true; onTriggered: root.rippleReady = true }
    NumberAnimation { id: arAnim; target: root; property: "arp"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
    function pingRipple() {
        if (autoRipple && cfgBar && Sys.onAC && rippleReady && visible) arAnim.restart();
    }
    // shake(): quick left-right shake plus one ring (switch: phonefile)
    property real shakeX: 0
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 45 }
        NumberAnimation { target: root; property: "shakeX"; to: 3; duration: 90 }
        NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 90 }
        NumberAnimation { target: root; property: "shakeX"; to: 2; duration: 80 }
        NumberAnimation { target: root; property: "shakeX"; to: -1; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60 }
    }
    function shake() {
        if (!cfgPhone || !Sys.onAC || !visible) return;
        shakeAnim.restart();
        arAnim.restart();
    }
    onLabelChanged: { pingRipple(); swapLabel(); }
    onIconChanged: pingRipple()
    onIconSvgChanged: pingRipple()

    Rectangle {
        visible: root.arp < 1
        width: 14 + 34 * root.arp
        height: width
        radius: width / 2
        x: body.x + body.width / 2 - width / 2
        y: body.y + body.height / 2 - height / 2
        color: "transparent"
        border.width: 1.5
        border.color: root.fgN
        opacity: (1 - root.arp) * 0.8
        z: 10
    }

    onPulseChanged: if (!pulse) phase = 0

    // true sine: a linear phase 0..2pi, so speed is highest at the middle (no stall at the centre)
    property bool bobWave: false      // with bob: a sine wave runs through the label letters
    property real bobPhase: 0
    readonly property bool bobbing: bob && cfgBob && visible
    readonly property bool waving: bobbing && bobWave
    onBobbingChanged: if (!bobbing) bobPhase = 0
    NumberAnimation on bobPhase {
        running: root.bobbing
        from: 0; to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
    }

    SequentialAnimation on phase {
        running: root.pulse && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: root.pulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: root.pulseMs; easing.type: Easing.InOutSine }
    }

    // weather animation (switch: weatherfx). wx = clear partly cloud fog drizzle rain snow storm; empty = off (set by the caller on AC only)
    property string wx: ""
    property real wxPhase: 0
    readonly property bool wxOn: wx !== "" && cfgWx && visible
    readonly property bool wxClouds: wxOn && wx === "cloud"
    readonly property bool wxFalling: wxOn && (wx === "rain" || wx === "drizzle" || wx === "snow")
    readonly property real wxFlash: wx === "storm" ? Math.pow(Math.max(0, Math.sin(wxPhase * 2 + 1)), 12) : 0
    readonly property real wxRot: !wxOn ? 0 : wx === "clear" ? wxPhase * 180 / Math.PI : wx === "storm" ? 6 * Math.sin(wxPhase * 14) * wxFlash : 0
    readonly property real wxScale: !wxOn ? 1 : wx === "clear" ? 1 + 0.08 * Math.sin(wxPhase * 2) : wx === "storm" ? 1 + 0.25 * wxFlash : 1
    readonly property real wxDx: !wxOn ? 0 : wx === "partly" ? 1.6 * Math.sin(wxPhase) : 0
    readonly property real wxDy: !wxOn ? 0 : wxFalling ? 0.6 * Math.sin(wxPhase * 2) : 0
    readonly property real wxOpacity: !wxOn ? 1 : wx === "fog" ? 0.55 + 0.45 * (0.5 + 0.5 * Math.sin(wxPhase)) : wx === "storm" ? 1 - 0.3 * wxFlash : 1
    onWxOnChanged: if (!wxOn) wxPhase = 0
    NumberAnimation on wxPhase {
        running: root.wxOn
        from: 0; to: Math.PI * 2
        duration: root.wx === "storm" ? 3600 : 4000
        loops: Animation.Infinite
    }

    onTipChanged: if (tipper && mouse.containsMouse) tipper.show(body, Markup.spaces(tip))
}
