import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

// SUPER+n per-app audio output, a port of ~/.config/hypr/rofi-audio-route.sh with rofi-audio-route.rosi.
// Nodes come from Quickshell.Services.Pipewire (live), so opening runs no pw-dump/jq.
// Two steps like the script: pick an app stream, then a sink.
MenuBox {
    id: root

    signal close

    property var stream: null  // null = picking the app

    // binds their properties (media.class etc.); always on, so opening needn't wait for them
    readonly property var audioNodes: Pipewire.nodes.values.filter(n => n.audio)
    PwObjectTracker { objects: root.audioNodes }

    function cls(n) {
        return n.properties["media.class"] || "";
    }
    readonly property var streams: audioNodes.filter(n => cls(n) === "Stream/Output/Audio")
    readonly property var sinks: audioNodes.filter(n => cls(n) === "Audio/Sink")

    function appName(n) {
        return n.properties["application.name"] || "";
    }

    // false = nothing to route, don't show
    function open() {
        stream = null;
        if (!streams.length) {
            Quickshell.execDetached(["notify-send", "Audio routing", "No app is playing audio"]);
            return false;
        }
        reset();
        return true;
    }

    items: stream
        ? sinks.map(n => ({ text: n.description || n.name, node: n }))
        : streams.map(n => ({ text: (appName(n) || n.name) + " - " + (n.properties["media.name"] || ""), node: n }))
    prompt: "AUDIO"
    placeholder: stream ? "Output for " + (appName(stream) || stream.name) : "Route app audio"

    // remember the choice per app so ~/.config/hypr/audio-route-watch.sh re-applies it to new streams
    FileView {
        id: routes
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/audio-routes"
        printErrors: false
        blockLoading: true
    }

    onPicked: item => {
        if (!stream) {
            stream = item.node;
            reset();
            return;
        }
        const sink = item.node.name;
        Quickshell.execDetached(["pw-metadata", "--", String(stream.id), "target.object", sink]);
        // names come from the apps: no tabs/newlines, or they could forge route lines
        const app = appName(stream).replace(/[\t\n]/g, " ");
        if (app && !/[\t\n]/.test(sink)) {
            routes.reload();
            const keep = routes.text().split("\n").filter(l => l && !l.startsWith(app + "\t"));
            routes.setText([...keep, app + "\t" + sink].join("\n") + "\n");
        }
        close();
    }
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F22A2619"; panel: Theme.isLight ? "#80D8D0BF" : "#805A5035"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2D8C983"
    borderColor: Theme.isLight ? "#9A937F" : "#CDBE78"; borderSoft: Theme.isLight ? "#B9B2A3" : "#8F8049"
    textColor: Theme.isLight ? "#2A2A2E" : "#F5F0DC"; textFaint: Theme.isLight ? "#6B6A70" : "#9A9272"; accent: Theme.isLight ? "#1A5FB4" : "#D99252"; selText: "#2A2312"
    glyphs: true  // Font Awesome icons in the text

    width: 840
    columns: 1; lines: 10; spacing: 10
    elemRadius: 20; padV: 12; padH: 14
}
