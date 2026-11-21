import QtQuick
import Quickshell
import ".."

// SUPER+space app list, a port of `rofi -show drun` with ~/.config/hypr/rofi-app-grid.rosi.
MenuBox {
    id: root

    required property var apps  // Apps.qml
    signal close

    function open() { reset(); }

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // rofi's default drun-display-format: name, then the generic name small and italic
    items: apps.apps.map(e => ({
        text: esc(e.name) + (e.genericName ? " <i><font size=\"2\">(" + esc(e.genericName) + ")</font></i>" : ""),
        icon: Quickshell.iconPath(e.icon, "application-x-executable"),
        meta: [e.name, e.genericName, ...e.keywords].join(" "),
        entry: e
    }))
    rich: true
    onPicked: item => { apps.launch(item.entry); close(); }
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F2313B34"; panel: Theme.isLight ? "#80D8D0BF" : "#8055645A"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2A5C4AE"
    borderColor: Theme.isLight ? "#9A937F" : "#8FA89A"; borderSoft: Theme.isLight ? "#B9B2A3" : "#738E7E"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#8DA193"; accent: Theme.isLight ? "#1A5FB4" : "#9AB9A5"; selText: "#17261d"
    prompt: "APPS"; placeholder: "Search applications"
    fontFamily: "JetBrainsMono Nerd Font"

    width: 920
    columns: 2; lines: 6; dynamic: false; spacing: 12
    elemRadius: 20; padV: 14; padH: 16; elemSpacing: 14
    iconSize: 38  // 2.4em at 12pt
}
