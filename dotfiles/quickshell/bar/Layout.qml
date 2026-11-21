pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Module order of each pill (Cap), changed by hold-dragging a chip.
// Kept in ~/.local/state/quickshell-bar/layout.json as {capName: [objectName, ...]}.
Singleton {
    id: root

    property var map: ({})
    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell-bar"

    function save(m) {
        map = m;
        file.setText(JSON.stringify(m));
    }

    Process {
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    FileView {
        id: file
        path: root.dir + "/layout.json"
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
