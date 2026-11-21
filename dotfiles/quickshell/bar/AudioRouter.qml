import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Re-applies the saved app->sink routes to every new audio stream (apps recreate
// streams on pause/resume). Port of ~/.config/hypr/audio-route-watch.sh: it ran
// bash + pw-dump + jq for the whole session; this reads the same PipeWire graph
// the bar already has open. The routes file is written by menus/AudioRoute.qml.
Item {
    id: root

    property var pending: []
    property var seen: ({})

    FileView {
        id: routes
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/audio-routes"
        printErrors: false
        blockLoading: true
    }

    function route(node) {
        if (seen[node.id] === node) return;   // ids are reused: compare the object
        const p = node.properties;
        if (!node.ready || !p) return;
        seen[node.id] = node;
        if (p["media.class"] !== "Stream/Output/Audio") return;
        const app = p["application.name"] || "";
        routes.reload();
        let sink = "";
        for (const l of routes.text().split("\n")) {
            const t = l.indexOf("\t");
            if (t > 0 && l.slice(0, t) === app) sink = l.slice(t + 1);   // last line wins
        }
        if (sink) Quickshell.execDetached(["pw-metadata", "--", String(node.id), "target.object", sink]);
    }

    PwObjectTracker { objects: root.pending }

    // a new node's properties arrive shortly after it appears; check until bound,
    // then drop it. (Not an Instantiator: an array model of nodes crashed Qt.)
    Timer {
        interval: 200
        repeat: true
        running: root.pending.length > 0
        onTriggered: {
            const left = [];
            for (const n of root.pending) {
                root.route(n);
                if (root.seen[n.id] !== n) left.push(n);
            }
            if (left.length !== root.pending.length) root.pending = left;   // re-assigning every tick would rebind the tracker forever
        }
    }

    Connections {
        target: Pipewire.nodes
        function onObjectInsertedPost(node, index) {
            if (node.audio) root.pending = [...root.pending, node];
        }
    }

    Component.onCompleted: pending = Pipewire.nodes.values.filter(n => n.audio)
}
