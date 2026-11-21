import QtQuick
import Quickshell
import Quickshell.Bluetooth
import ".."

// SUPER+b Bluetooth menu, a port of ~/.config/hypr/rofi-bluetooth-menu.sh with rofi-bluetooth.rosi.
// Talks to BlueZ through Quickshell.Bluetooth (D-Bus events), so nothing runs on open.
// Two levels like the script: adapter actions + devices, then one device's actions.
MenuBox {
    id: root

    signal close

    readonly property var adapter: Bluetooth.defaultAdapter
    property var device: null  // null = main list
    // the picked device while BlueZ still has it (a scan result can vanish while its submenu is open)
    readonly property var dev: device && Bluetooth.devices.values.includes(device) ? device : null

    function open() {
        device = null;
        reset();
    }

    function tags(d) {
        const t = [];
        if (d.connected) t.push("connected");
        if (d.paired) t.push("paired");
        if (d.trusted) t.push("trusted");
        return t.length ? " [" + t.join(",") + "]" : "";
    }

    readonly property var mainItems: {
        const on = adapter && adapter.enabled;
        const list = [
            { text: "  Bluetooth: " + (on ? "on" : "off"), act: "power" },
            { text: "  Open Blueman", act: "blueman" },
            { text: "  Scan Devices", act: "scan" }
        ];
        for (const d of Bluetooth.devices.values)
            list.push({ text: (d.blocked ? "" : "") + "  " + (d.name || d.address) + tags(d), dev: d });
        return list;
    }

    readonly property var deviceItems: dev ? [
        dev.connected ? { text: "  Disconnect", act: "disconnect" } : { text: "  Connect", act: "connect" },
        dev.trusted ? { text: "  Untrust", act: "untrust" } : { text: "  Trust", act: "trust" },
        dev.blocked ? { text: "  Unblock", act: "unblock" } : { text: "  Block", act: "block" },
        ...(dev.paired ? [{ text: "  Remove", act: "remove" }] : []),
        { text: "  Back", act: "back" }
    ] : []

    items: dev ? deviceItems : mainItems
    prompt: "BT"
    placeholder: dev ? (dev.name || dev.address) : "Bluetooth devices and actions"

    onPicked: item => {
        const d = dev;
        switch (item.act) {
        case "power": if (adapter) adapter.enabled = !adapter.enabled; break;
        case "blueman": Quickshell.execDetached(["blueman-manager"]); break;
        case "scan": if (adapter) { adapter.discovering = true; scanStop.restart(); } break;
        case "connect": d.connect(); break;
        case "disconnect": d.disconnect(); break;
        case "trust": d.trusted = true; break;
        case "untrust": d.trusted = false; break;
        case "block": d.blocked = true; break;
        case "unblock": d.blocked = false; break;
        case "remove": d.forget(); break;
        case "back": break;
        default:
            if (item.dev) {  // into the device's actions, like the script's second rofi
                device = item.dev;
                reset();
                return;
            }
        }
        close();
    }
    onCancelled: close()

    // we keep the D-Bus connection open, so BlueZ would scan until told to stop: stop after 30s (battery)
    Timer {
        id: scanStop
        interval: 30000
        onTriggered: if (root.adapter) root.adapter.discovering = false
    }

    bg: Theme.isLight ? "#F2F6F1E7" : "#F22E3440"; panel: Theme.isLight ? "#80D8D0BF" : "#804C566A"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F28AC0D0"
    borderColor: Theme.isLight ? "#9A937F" : "#81A1C1"; borderSoft: Theme.isLight ? "#B9B2A3" : "#5E81AC"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#7B88A1"; accent: Theme.isLight ? "#1A5FB4" : "#88C0D0"; selText: "#17212a"
    glyphs: true  // Font Awesome icons in the text

    width: 840
    columns: 1; lines: 10; spacing: 10
    elemRadius: 20; padV: 12; padH: 14
}
