import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// SUPER+Escape keybind list, a port of ~/.config/hypr/rofi-keybinds.sh with rofi-keybinds.rosi.
// Rows come from `rofi-keybinds.sh --print`, rerun only when its source files change.
MenuBox {
    id: root

    required property var screenItem  // for the 90% x 92% window size
    signal close

    function open() { reset(); }

    readonly property string dir: Quickshell.env("HOME") + "/.config/hypr"

    Process {
        id: rows
        running: true
        command: [root.dir + "/rofi-keybinds.sh", "--print"]
        stdout: StdioCollector {
            onStreamFinished: root.items = text.split("\n").filter(l => l).map(l => ({ text: l }))
        }
    }

    FileView {
        path: root.dir + "/hyprland.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: rows.running = true
    }
    FileView {
        path: root.dir + "/keybinds.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: rows.running = true
    }

    onPicked: close()  // rofi just closed on Enter too
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F23B3133"; panel: Theme.isLight ? "#80D8D0BF" : "#8064555A"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2C4A5AB"
    borderColor: Theme.isLight ? "#9A937F" : "#A88F94"; borderSoft: Theme.isLight ? "#B9B2A3" : "#8E7378"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#A18D91"; accent: Theme.isLight ? "#1A5FB4" : "#B99AA0"; selText: "#26171A"
    prompt: "KEYS"; placeholder: "Search keybinds"
    glyphs: true  // Font Awesome icons in the text
    fontPt: 11

    width: screenItem.width * 0.9
    columns: 4; lines: 16; spacing: 10
    elemRadius: 16; padV: 10; padH: 14
}
