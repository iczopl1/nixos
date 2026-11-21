import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// SUPER+F3: draw on the screen (replaces wayscriber). Works with touch, pen and mouse.
// While on, the overlay takes all input. Keys (wayscriber's): hold Shift = line, Ctrl = rectangle,
// Tab = ellipse, Ctrl+Shift = arrow while you drag. Esc/q close, Ctrl+Z undo, Ctrl+Shift+Z redo,
// E (or c) clear, R G B Y O P W K colors (also 1-8), + / - pen width,
// Ctrl+W whiteboard, Ctrl+B blackboard, Ctrl+Shift+T back to see-through.
// The small toolbar does the same for touch.
// Toggle:  socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-draw-$WAYLAND_DISPLAY.sock
//          qs -c bar ipc call draw toggle
Scope {
    id: root

    property bool active: false
    property color pen: "#ff3b30"
    property int penWidth: 4
    readonly property var palette: ["#ff3b30", "#34c759", "#0a84ff", "#ffd84a", "#ff9500", "#ff6bb5", "#ffffff", "#000000"]
    readonly property string colorKeys: "RGBYOPWK"
    property string board: "transparent"     // transparent | whiteboard | blackboard

    function toggle() { active = !active; }
    onActiveChanged: if (active) board = "transparent"   // always open see-through

    IpcHandler {
        target: "draw"
        function toggle(): void { root.toggle(); }
    }

    SocketServer {
        id: server
        active: true
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-menu-draw-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        handler: Socket {
            Component.onCompleted: root.toggle()
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active

            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // Top, not Overlay: power-fx's cursor trail lives on an Overlay window, so the strokes sit under it
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "qs-draw"

            property var strokes: []      // finished + live: [{c, w, pts: [x, y, x, y, ...]}]
            property var live: ({})       // pointId -> stroke being drawn
            property var redoStack: []
            property bool ctrl: false
            property bool shift: false
            property bool tab: false
            readonly property string tool: ctrl && shift ? "arrow" : shift ? "line" : ctrl ? "rect" : tab ? "ellipse" : "free"

            function undo() {
                var s = strokes.pop();
                if (s) redoStack.push(s);
                canvas.requestPaint();
            }
            function redo() {
                var s = redoStack.pop();
                if (s) strokes.push(s);
                canvas.requestPaint();
            }
            function clear() {
                strokes = [];
                redoStack = [];
                live = ({});
                canvas.requestPaint();
            }
            onVisibleChanged: if (!visible) clear()

            Item {
                id: field
                anchors.fill: parent
                focus: root.active
                onFocusChanged: if (focus) forceActiveFocus()

                Keys.onReleased: e => {
                    win.ctrl = !!(e.modifiers & Qt.ControlModifier);
                    win.shift = !!(e.modifiers & Qt.ShiftModifier);
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) win.tab = false;
                    e.accepted = true;
                }
                Keys.onPressed: e => {
                    e.accepted = true;
                    win.ctrl = !!(e.modifiers & Qt.ControlModifier);
                    win.shift = !!(e.modifiers & Qt.ShiftModifier);
                    var ctrl = win.ctrl, shift = win.shift;
                    var ci = root.colorKeys.indexOf(String.fromCharCode(e.key));
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)
                        win.tab = true;
                    else if (e.key === Qt.Key_Escape || (e.key === Qt.Key_Q && !ctrl))
                        root.active = false;
                    else if (e.key === Qt.Key_Z && ctrl && shift)
                        win.redo();
                    else if (e.key === Qt.Key_Z && ctrl || e.key === Qt.Key_U)
                        win.undo();
                    else if (e.key === Qt.Key_Y && ctrl)
                        win.redo();
                    else if (e.key === Qt.Key_W && ctrl)
                        root.board = root.board === "whiteboard" ? "transparent" : "whiteboard";
                    else if (e.key === Qt.Key_B && ctrl)
                        root.board = root.board === "blackboard" ? "transparent" : "blackboard";
                    else if (e.key === Qt.Key_T && ctrl && shift)
                        root.board = "transparent";
                    else if (e.key === Qt.Key_E || e.key === Qt.Key_C)
                        win.clear();
                    else if (!ctrl && ci >= 0)
                        root.pen = root.palette[ci];
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8)
                        root.pen = root.palette[e.key - Qt.Key_1];
                    else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)
                        root.penWidth = Math.min(40, root.penWidth + 2);
                    else if (e.key === Qt.Key_Minus)
                        root.penWidth = Math.max(1, root.penWidth - 2);
                }

                // faint tint so you can see draw mode is on
                Rectangle {
                    anchors.fill: parent
                    color: root.board === "whiteboard" ? "#f5f5f5" : root.board === "blackboard" ? "#1a1a1a" : "#10000000"
                }

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    renderTarget: Canvas.FramebufferObject
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        for (var s of win.strokes) {
                            ctx.strokeStyle = s.c;
                            ctx.fillStyle = s.c;
                            ctx.lineWidth = s.w;
                            var p = s.pts;
                            if (s.kind && s.kind !== "free" && p.length >= 4) {
                                var x0 = p[0], y0 = p[1], x1 = p[p.length - 2], y1 = p[p.length - 1];
                                ctx.beginPath();
                                if (s.kind === "rect") {
                                    ctx.rect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
                                } else if (s.kind === "ellipse") {
                                    ctx.ellipse(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
                                } else {
                                    ctx.moveTo(x0, y0);
                                    ctx.lineTo(x1, y1);
                                    if (s.kind === "arrow") {
                                        var a = Math.atan2(y1 - y0, x1 - x0), h = Math.max(14, s.w * 4);
                                        ctx.moveTo(x1, y1);
                                        ctx.lineTo(x1 - h * Math.cos(a - 0.45), y1 - h * Math.sin(a - 0.45));
                                        ctx.moveTo(x1, y1);
                                        ctx.lineTo(x1 - h * Math.cos(a + 0.45), y1 - h * Math.sin(a + 0.45));
                                    }
                                }
                                ctx.stroke();
                                continue;
                            }
                            if (p.length === 2) {
                                ctx.beginPath();
                                ctx.arc(p[0], p[1], s.w / 2, 0, 6.2832);
                                ctx.fill();
                                continue;
                            }
                            ctx.beginPath();
                            ctx.moveTo(p[0], p[1]);
                            for (var i = 2; i < p.length; i += 2)
                                ctx.lineTo(p[i], p[i + 1]);
                            ctx.stroke();
                        }
                    }
                }

                // Touch (multi-finger), pen and mouse all arrive here.
                MultiPointTouchArea {
                    anchors.fill: parent
                    maximumTouchPoints: 10
                    mouseEnabled: true
                    onTouchUpdated: pts => {
                        var changed = false;
                        for (var t of pts) {
                            var s = win.live[t.pointId];
                            if (t.pressed) {
                                if (!s) {
                                    s = { c: String(root.pen), w: root.penWidth, kind: win.tool, pts: [t.x, t.y] };
                                    win.redoStack = [];
                                    win.live[t.pointId] = s;
                                    win.strokes.push(s);
                                } else {
                                    s.pts.push(t.x, t.y);
                                    s.kind = win.tool;
                                }
                                changed = true;
                            } else if (s) {
                                delete win.live[t.pointId];
                            }
                        }
                        if (changed)
                            canvas.requestPaint();
                    }
                    onReleased: pts => {
                        for (var t of pts)
                            delete win.live[t.pointId];
                    }
                }

                // toolbar, top centre
                Rectangle {
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 12 }
                    width: bar.implicitWidth + 24
                    height: 56
                    radius: 28
                    color: "#d0202020"
                    border.color: "#40ffffff"

                    Row {
                        id: bar
                        anchors.centerIn: parent
                        spacing: 10

                        Repeater {
                            model: root.palette
                            Rectangle {
                                required property string modelData
                                width: 36; height: 36; radius: 18
                                color: modelData
                                border.width: root.pen === modelData ? 3 : 1
                                border.color: root.pen === modelData ? "#ffffff" : "#80808080"
                                MouseArea { anchors.fill: parent; onClicked: root.pen = parent.modelData }
                            }
                        }
                        Repeater {
                            model: [
                                { t: "−", f: () => root.penWidth = Math.max(1, root.penWidth - 2) },
                                { t: "+", f: () => root.penWidth = Math.min(40, root.penWidth + 2) },
                                { t: "↶", f: () => win.undo() },
                                { t: "🗑", f: () => win.clear() },
                                { t: "✕", f: () => root.active = false }
                            ]
                            Rectangle {
                                required property var modelData
                                width: 36; height: 36; radius: 18
                                color: "#40ffffff"
                                Text { anchors.centerIn: parent; text: parent.modelData.t; color: "white"; font.pixelSize: 20 }
                                MouseArea { anchors.fill: parent; onClicked: parent.modelData.f() }
                            }
                        }
                    }
                }
            }
        }
    }
}
