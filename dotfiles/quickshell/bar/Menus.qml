import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "menus"

// The rofi menus and the SUPER-tap launcher, all in the bar process.
// Every menu is built at startup inside one overlay surface that stays mapped
// while hidden (see-through, click-through, no keyboard), so opening one is a
// repaint, not a new surface. Hidden menus are not drawn, so they cost no CPU.
//
// Each menu has its own socket; every connection toggles it (~7ms, no shell):
//   socat -u /dev/null UNIX-CONNECT:$XDG_RUNTIME_DIR/qs-menu-<name>-$WAYLAND_DISPLAY.sock
// The launcher keeps its old socket, qs-launcher-$WAYLAND_DISPLAY.sock. Slow fallback:
//   qs -c bar ipc call menus toggle <name>
Scope {
    id: root

    readonly property var names: ["launcher", "apps", "clip", "emoji", "bluetooth", "audio", "keybinds", "wallpaper", "wallhaven", "display", "dance"]
    property string current: ""  // "" = all hidden

    signal dance(string pattern)  // the dance menu picked a pattern; shell.qml hands it to Fx

    function menu(name) {
        return { launcher: launcher, apps: appGrid, clip: clip, emoji: emoji, bluetooth: bluetooth,
                 audio: audio, keybinds: keybinds, wallpaper: wallpaper, wallhaven: wallhaven, display: display, dance: danceMenu }[name];
    }

    function toggle(name) {
        if (current === name) {
            current = "";
            return;
        }
        if (!menu(name))
            return;
        // open on the monitor the pointer is on (the overlay is one window; it moves screens)
        if (!Mango.active) {
            show(name);
            return;
        }
        if (cursor.running)
            return;
        pending = name;
        cursor.running = true;
    }

    property string pending: ""

    function show(name) {
        current = name;
        if (menu(name).open() === false)
            current = "";
    }

    // Screen that shows the menus. The menu content (holder) is built once and moved into
    // that screen's overlay window; the windows themselves are made at startup and never
    // re-created, so they stay under power-fx's cursor window in the stacking order.
    property string target: ""

    Process {
        id: cursor
        command: ["mmsg", "get", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const n = JSON.parse(text).monitor;
                    if (Quickshell.screens.some(x => x.name === n))
                        root.target = n;
                } catch (e) {}
                root.show(root.pending);
            }
        }
    }

    function close() {
        current = "";
    }

    IpcHandler {
        target: "menus"

        function toggle(name: string): void {
            root.toggle(name);
        }
    }

    Variants {
        model: root.names
        SocketServer {
            id: server
            required property string modelData
            active: true
            path: Quickshell.env("XDG_RUNTIME_DIR") + "/"
                + (modelData === "launcher" ? "qs-launcher-" : "qs-menu-" + modelData + "-")
                + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
            handler: Socket {
                Component.onCompleted: root.toggle(server.modelData)
            }
        }
    }

    Apps { id: appList }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            readonly property bool here: root.target !== "" ? root.target === modelData.name : modelData === Quickshell.screens[0]
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region { item: w.here && root.current ? backdrop : null }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: w.here && root.current ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "qs-launcher"

            onHereChanged: if (here) holder.parent = contentItem
            Component.onCompleted: if (here) holder.parent = contentItem
            // never take the menus down with a window that goes away (screen unplugged)
            Component.onDestruction: if (holder.parent === contentItem) holder.parent = null
        }
    }

    Item {
        id: holder
        anchors.fill: parent

        // click outside the box closes, like rofi
        MouseArea {
            id: backdrop
            anchors.fill: parent
            onClicked: root.close()
        }

        AppIcons {
            id: launcher
            apps: appList
            visible: root.current === "launcher"
            anchors.centerIn: parent
            onClose: root.close()
        }
        AppGrid {
            id: appGrid
            apps: appList
            visible: root.current === "apps"
            anchors.centerIn: parent
            onClose: root.close()
        }
        Clipboard {
            id: clip
            visible: root.current === "clip"
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 }
            onClose: root.close()
        }
        Emoji {
            id: emoji
            visible: root.current === "emoji"
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 }
            onClose: root.close()
        }
        Bluetooth {
            id: bluetooth
            visible: root.current === "bluetooth"
            anchors.centerIn: parent
            onClose: root.close()
        }
        AudioRoute {
            id: audio
            visible: root.current === "audio"
            anchors.centerIn: parent
            onClose: root.close()
        }
        Keybinds {
            id: keybinds
            screenItem: backdrop
            visible: root.current === "keybinds"
            anchors.centerIn: parent
            onClose: root.close()
        }
        Wallpaper {
            id: wallpaper
            screenItem: backdrop
            visible: root.current === "wallpaper"
            anchors.centerIn: parent
            onClose: root.close()
        }
        Display {
            id: display
            visible: root.current === "display"
            anchors.centerIn: parent
            onClose: root.close()
        }
        Dance {
            id: danceMenu
            visible: root.current === "dance"
            anchors.centerIn: parent
            onClose: root.close()
            onDance: pattern => root.dance(pattern)
        }
        WallhavenSearch {
            id: wallhaven
            screenItem: backdrop
            visible: root.current === "wallhaven"
            anchors.centerIn: parent
            onClose: root.close()
        }
    }
}
