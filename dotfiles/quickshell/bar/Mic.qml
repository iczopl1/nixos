pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Mic-in-use indicator, a port of `wbw mic` (waybar/rust/src/mic.rs). That was a
// Rust process plus a second `pw-dump --monitor`; this reads the PipeWire graph
// the bar already has open. A recorder is a capture stream with an active link
// from a real mic (Audio/Source or Audio/Duplex, not a sink monitor).
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    PwObjectTracker { objects: root.nodes }
    PwObjectTracker { objects: Pipewire.linkGroups.values }

    function prop(n, k) {
        const v = n && n.properties ? n.properties[k] : undefined;
        return v === undefined || v === null ? "" : String(v);
    }

    function truthy(n, k) {
        const v = prop(n, k);
        return v !== "" && v !== "0" && v !== "false";
    }

    // [{app, mic, muted}] for every running capture from a mic
    readonly property var recs: {
        const out = [], seen = {};
        for (const lg of Pipewire.linkGroups.values) {
            const t = lg.target, s = lg.source;
            if (!t || !s || lg.state !== PwLinkState.Active) continue;
            if (prop(t, "media.class") !== "Stream/Input/Audio") continue;
            if (truthy(t, "stream.capture.sink") || truthy(t, "stream.monitor")) continue;
            const sc = prop(s, "media.class");
            if (sc !== "Audio/Source" && sc !== "Audio/Duplex") continue;
            const app = prop(t, "application.name") || prop(t, "application.process.binary") || prop(t, "node.name") || "?";
            const mic = prop(s, "node.description") || prop(s, "node.name") || "mic";
            const muted = s.audio ? s.audio.muted : false;
            const key = app + "\t" + mic;
            if (seen[key]) continue;
            seen[key] = true;
            out.push({ app: app, mic: mic, muted: muted });
        }
        return out;
    }

    readonly property bool active: recs.length > 0
    readonly property bool muted: active && recs.every(r => r.muted)
    readonly property string label: {
        const apps = [...new Set(recs.map(r => r.app))];
        return (muted ? "mic muted" : "mic live") + (apps.length ? " · " + apps.join(", ") : "");
    }

    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    readonly property string tooltip: {
        if (!active) return "";
        const lines = ["<b>" + (muted ? "Mic muted" : "Mic live") + "</b>"];
        for (const r of recs)
            lines.push(esc(r.app) + "  <small>" + esc(r.mic) + (r.muted ? " (muted)" : "") + "</small>");
        lines.push("<small>middle: mute / unmute   right-click: recording mixer</small>");
        return lines.join("<br>");
    }
}
