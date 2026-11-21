// Lock screen, a port of ~/.config/hypr/hyprlock.conf. Lives inside the bar
// process (one Quickshell, not two). Driven by ~/.config/hypr/qs-lock.sh:
//   qs -c bar ipc call lock lock       lock now
//   qs -c bar ipc call lock test <s>   lock, unlock by itself after <s> seconds
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    property string wallpaper: ""  // real file behind ~/.cache/hyprlock-wallpaper
    readonly property string font: "JetBrains Mono NL"
    property string buffer: ""
    property int attempts: 0
    property bool failed: false
    property color ring: Theme.isLight ? Qt.rgba(26 / 255, 95 / 255, 180 / 255, 0.85) : Qt.rgba(160 / 255, 190 / 255, 1, 0.85)
    property bool shown: false  // fades in over / out to the live desktop (lock surface is see-through)

    // live AC check for the wobble (Sys.acOnline only refreshes every 60 s)
    property bool onAC: false
    // switch from power-fx's effects.conf (a line without # = on)
    property bool cfgWobble: true
    FileView {
        path: "/home/iczo/syshelp/power-fx/effects.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.cfgWobble = /\n\s*lockwobble(\s|$)/.test("\n" + text())
    }
    Process {
        id: acProc
        command: ["sh", "-c", "cat /sys/class/power_supply/AC/online 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.onAC = text.indexOf("1") >= 0
        }
    }
    Timer {
        interval: 2000
        running: lock.locked
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!acProc.running) acProc.running = true
    }

    // letters bob up and down in a wave
    component Wobble: Row {
        id: wob
        property string text: ""
        property int pointSize: 20
        property real amp: 3
        property real phase: 0
        NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 5000; loops: Animation.Infinite; running: wob.visible && root.onAC && root.cfgWobble }
        Repeater {
            model: wob.text.length
            Text {
                required property int index
                text: wob.text[index]
                color: Theme.ink
                font { family: root.font; pointSize: wob.pointSize }
                transform: Translate { y: root.onAC && root.cfgWobble ? Math.sin(wob.phase + index * 0.9) * wob.amp : 0 }
            }
        }
    }

    function lockNow(testSecs) {
        if (lock.locked)
            return;
        buffer = "";
        attempts = 0;
        failed = false;
        shown = false;
        readWallpaper.running = true;
        lock.locked = true;
        if (testSecs > 0) {
            testTimer.interval = testSecs * 1000;
            testTimer.start();
        }
    }

    function submit() {
        if (pam.active || buffer === "")
            return;
        failed = false;
        pam.start();
    }

    function unlock() {
        if (!lock.locked || unlockTimer.running)
            return;
        testTimer.stop();
        shown = false;
        unlockTimer.start();
    }

    PamContext {
        id: pam
        // "swaylock" doesn't exist on this system (/etc/pam.d/other then denies
        // everything unconditionally – correct passwords never unlocked). "hyprlock"
        // is the PAM service NixOS already creates via programs.hyprlock.enable;
        // same plain pam_unix rules, and it exists here.
        config: "hyprlock"
        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(root.buffer);
                root.buffer = "";
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlock();
            } else {
                root.attempts++;
                root.failed = true;
                root.buffer = "";
            }
        }
    }

    // fade out, then release the session
    Timer {
        id: unlockTimer
        interval: 500
        onTriggered: {
            lock.locked = false;
        }
    }

    Timer {
        id: testTimer
        onTriggered: root.unlock()
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lockNow(0); }
        function test(secs: int): void { root.lockNow(secs); }
    }

    // started by qs-lock.sh when the background lock wasn't running yet
    Component.onCompleted: {
        const now = parseInt(Quickshell.env("QS_LOCK_NOW") || "-1");
        if (now >= 0)
            lockNow(now);
    }

    // follow wallpaper changes and decode the new one ahead of time, at screen size
    Process {
        id: readWallpaper
        running: true
        command: ["readlink", "-f", Quickshell.env("HOME") + "/.cache/hyprlock-wallpaper"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "")
                    root.wallpaper = "file://" + p;
            }
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: !lock.locked
        onTriggered: readWallpaper.running = true
    }
    Variants {
        model: Quickshell.screens
        Image {
            required property var modelData
            source: root.wallpaper
            sourceSize: Qt.size(modelData.width, modelData.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    WlSessionLock {
        id: lock
        locked: false
        onSecureChanged: if (secure) root.shown = true

        WlSessionLockSurface {
            id: surface
            // see-through, so the fade shows the live desktop. Needs mango
            // allow_lock_transparent=1 / hyprland misc:session_lock_xray = true
            color: "transparent"

            Item {
                anchors.fill: parent
                opacity: root.shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 500  // hyprlock fadeIn/fadeOut 5, curve 0,1.2,.8,1
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0, 1.2, 0.8, 1, 1, 1]
                    }
                }

                // background: wallpaper, blur 2x2, contrast .8, brightness .6, vibrancy .21
                // hyprlock math: contrast c' = (c - .5) * .8 + .5, brightness c' = c * .6,
                // done below as a 20% mid-grey layer then a 40% black layer
                Image {
                    id: wall
                    anchors.fill: parent
                    // same source + size as the preload above, so it comes from Qt's cache;
                    // empty until the screen is known so a 0x0 size can't force a full decode
                    source: surface.screen ? root.wallpaper : ""
                    sourceSize: surface.screen ? Qt.size(surface.screen.width, surface.screen.height) : Qt.size(0, 0)
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: wall
                    blurEnabled: true
                    blur: 0.6
                    blurMax: 32
                    saturation: 0.25
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.isLight ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.4)
                }

                Wobble {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -250
                    text: Qt.formatDateTime(clock.date, "ddd, MMM dd ''yy")
                    pointSize: 20
                    amp: 2
                }
                Wobble {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -120
                    text: Qt.formatDateTime(clock.date, "HH")
                    pointSize: 150
                    amp: 6
                }
                Wobble {
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ss")
                    pointSize: 40
                    amp: 3
                }
                Wobble {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 120
                    text: Qt.formatDateTime(clock.date, "mm")
                    pointSize: 150
                    amp: 6
                }

                // input field: hidden input, ring changes colour per key, fades when empty
                Rectangle {
                    id: field
                    readonly property bool idle: root.buffer === "" && !pam.active && !root.failed
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 270
                    width: 350
                    height: 56
                    radius: 12
                    color: Theme.isLight ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(20 / 255, 24 / 255, 31 / 255, 0.3)
                    border.width: 3
                    border.color: pam.active ? Qt.rgba(160 / 255, 190 / 255, 1, 1)
                                : root.failed ? Qt.rgba(1, 120 / 255, 120 / 255, 1)
                                : root.ring
                    opacity: idle && fadeTimer.done ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Timer {
                        id: fadeTimer
                        property bool done: false
                        interval: 2000
                        running: field.idle
                        onRunningChanged: if (running) done = false
                        onTriggered: done = true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.failed ? "Wrong password (" + root.attempts + ")"
                            : root.buffer !== "" ? "*".repeat(root.buffer.length)
                            : !pam.active ? "123" : ""
                        color: root.failed ? Qt.rgba(1, 120 / 255, 120 / 255, 1) : Theme.isLight ? Qt.rgba(0.16, 0.16, 0.18, 0.6) : Qt.rgba(235 / 255, 239 / 255, 244 / 255, root.failed ? 1 : 0.5)
                        font { family: root.font; pixelSize: 16; italic: !(root.buffer !== "" && !root.failed) }
                    }
                }
            }

            // hide the cursor
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.BlankCursor
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (pam.active)
                        return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submit();
                    } else if (event.key === Qt.Key_Backspace) {
                        root.buffer = event.modifiers & Qt.ControlModifier ? "" : root.buffer.slice(0, -1);
                    } else if (event.key === Qt.Key_Escape) {
                        root.buffer = "";
                    } else if (event.text !== "" && event.text.charCodeAt(0) >= 32) {
                        root.buffer += event.text;
                        root.failed = false;
                        root.ring = Qt.hsva(Math.random(), 0.45, 1, 0.85);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
        }
    }
}
