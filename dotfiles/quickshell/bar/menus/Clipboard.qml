import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// SUPER+v clipboard history, a port of ~/.config/hypr/cliphist-rofi-img-pretty with rofi-clipboard.rosi.
// Opening shows the last list at once and reruns `cliphist list` (a few ms, no shell).
// Image previews are decoded once into $XDG_RUNTIME_DIR/qs-clip (only you can read it),
// not /tmp/cliphist like the rofi script.
MenuBox {
    id: root

    signal close

    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-clip"
    readonly property var imageRe: /^(\d+)\s+\[\[\s+binary\s+data\s+(.+)\s+(jpg|jpeg|png|bmp|gif|webp)\s+(\d+x\d+)\s+\]\]$/
    readonly property var metaRe: /^\d+\s+<meta\s+http-equiv=/
    property var rows: []
    property var decoded: ({})  // "<id>.<ext>" -> true once written

    function open() {
        reset();
        list.running = true;
    }

    function build() {
        const out = [];
        for (const line of rows) {
            if (metaRe.test(line))
                continue;
            const t = line.indexOf("\t");
            const id = line.slice(0, t);
            if (t < 0 || !/^\d+$/.test(id))
                continue;
            const m = line.match(imageRe);
            if (m) {
                const file = id + "." + m[3];
                out.push({ text: m[3].toUpperCase() + " image " + m[4] + " " + m[2], id: id, file: file,
                           icon: decoded[file] ? "file://" + dir + "/" + file : "" });
            } else {
                out.push({ text: line.slice(t + 1), id: id });
            }
        }
        items = out;
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rows = text.split("\n").filter(l => l);
                root.build();
                const files = root.items.filter(i => i.file).map(i => i.file);
                // always once per bar start: clears previews left by an earlier run
                if (!decode.ranOnce || files.some(f => !root.decoded[f]) || Object.keys(root.decoded).length !== files.length)
                    decode.start(files);
            }
        }
    }

    // write missing previews, drop ones no longer in the history; prints the ones that exist
    Process {
        id: decode
        property bool ranOnce: false
        property var next: null  // files asked for while running: run again after

        function start(files) {
            if (running) {
                next = files;
                return;
            }
            command = ["sh", "-c", `umask 077; d=$1; shift
mkdir -p "$d"
for f in "$d"/*; do [ -e "$f" ] || continue; case " $* " in *" \${f##*/} "*) ;; *) rm -f "$f" ;; esac; done
for e; do [ -s "$d/$e" ] || printf '%s\\t' "\${e%%.*}" | cliphist decode > "$d/$e"; [ -s "$d/$e" ] && echo "$e"; done; true`, "_", root.dir, ...files];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const d = {};
                for (const f of text.split("\n").filter(f => f))
                    d[f] = true;
                root.decoded = d;
                root.build();
            }
        }
        onExited: {
            ranOnce = true;
            root.build();
            if (next) {
                const f = next;
                next = null;
                start(f);
            }
        }
    }

    onPicked: item => {
        close();
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t' \"$1\" | cliphist decode | wl-copy --foreground --sensitive", "_", item.id]);
    }
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F2332E40"; panel: Theme.isLight ? "#80D8D0BF" : "#80564C6A"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2C78AD0"
    borderColor: Theme.isLight ? "#9A937F" : "#A181C1"; borderSoft: Theme.isLight ? "#B9B2A3" : "#815EAC"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#9483A8"; accent: Theme.isLight ? "#1A5FB4" : "#C088D0"; selText: "#1f1726"
    prompt: "CLIP"; placeholder: "Search clipboard history"
    fontFamily: "JetBrainsMono Nerd Font"

    width: 860
    columns: 1; lines: 9; spacing: 10
    elemRadius: 20; padV: 10; padH: 14; elemSpacing: 14
    iconSize: 64; iconRadius: 14; iconCache: false
}
