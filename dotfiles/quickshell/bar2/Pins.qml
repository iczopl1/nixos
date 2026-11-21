pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which chips are pinned open, kept in ~/.local/state/quickshell-bar2/pins.json
// so the state survives bar restarts. Keys are the chips' pinKey.
Singleton {
    id: root

    property var map: ({})
    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell-bar2"

    function set(key, on) {
        const m = Object.assign({}, map);
        if (on) m[key] = true;
        else delete m[key];
        map = m;
        file.setText(JSON.stringify(m));
    }

    Process {
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    FileView {
        id: file
        path: root.dir + "/pins.json"
        blockLoading: true
        atomicWrites: true
    }

    Component.onCompleted: {
        try {
            const m = JSON.parse(file.text());
            if (m && typeof m === "object") map = m;
        } catch (e) {}
    }
}
