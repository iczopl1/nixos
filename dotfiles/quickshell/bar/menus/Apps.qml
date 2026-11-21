import QtQuick
import Quickshell
import Quickshell.Io

// Apps for both launchers, sorted by launch count. Counts are shared with rofi
// drun: "<count> <id>.desktop" per line in ~/.cache/rofi3.druncache.
Scope {
    id: root

    property var counts: ({})
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => (counts[key(b)] || 0) - (counts[key(a)] || 0) || a.name.localeCompare(b.name))

    function key(e) {
        return e.id.endsWith(".desktop") ? e.id : e.id + ".desktop";
    }

    FileView {
        id: history
        path: Quickshell.env("HOME") + "/.cache/rofi3.druncache"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const c = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^(\d+) (.+)$/);
                if (m)
                    c[m[2]] = parseInt(m[1]);
            }
            root.counts = c;
        }
    }

    function launch(e) {
        if (!e)
            return;
        const c = Object.assign({}, counts);
        c[key(e)] = (c[key(e)] || 0) + 1;
        counts = c;
        history.setText(Object.keys(c).sort((a, b) => c[b] - c[a]).map(k => c[k] + " " + k).join("\n") + "\n");
        e.execute();
    }
}
