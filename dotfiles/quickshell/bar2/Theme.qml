pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colors come from waybar's colors.css (written by apply-wal-theme.py), so a
// wal re-theme recolors this bar too. Helpers mirror GTK's CSS color functions.
Singleton {
    id: root

    property var col: ({})
    readonly property string font: "Noto Sans"
    readonly property int fontPx: 12

    // Pango picks icon fonts per glyph through fontconfig; Qt does not. Ask
    // fc-match once per private-use glyph (as pango would for DejaVu Sans)
    // and wrap each one in the font it named.
    property var glyphFont: ({})
    property var _pending: []

    function icons(s) {
        const map = glyphFont;
        return s.replace(/([\ue000-\uf8ff]|[\udb80-\udbff][\udc00-\udfff])/g, ch => {
            const f = map[ch];
            if (f === undefined) {
                lookup(ch);
                return ch;
            }
            return "<span style=\"font-family:'" + f.family + "';font-weight:" + f.weight + "\">" + ch + "</span>";
        });
    }

    function lookup(ch) {
        if (_pending.indexOf(ch) >= 0) return;
        _pending.push(ch);
        if (!fc.running) fcNext();
    }

    function fcNext() {
        if (_pending.length === 0) return;
        const hex = _pending[0].codePointAt(0).toString(16);
        fc.command = ["fc-match", "-f", "%{family[0]}|%{style}", font + ":charset=" + hex];
        fc.running = true;
    }

    Process {
        id: fc
        onExited: root.fcNext()
        stdout: StdioCollector {
            onStreamFinished: {
                const [family, style] = text.split("|");
                const ch = root._pending.shift();
                const m = Object.assign({}, root.glyphFont);
                m[ch] = { family: family, weight: /Solid|Black|Heavy/.test(style) ? 900 : 400 };
                root.glyphFont = m;
            }
        }
    }

    function c(name) {
        return col[name] !== undefined ? col[name] : "#ff00ff";
    }

    // GTK shade(): scale lightness and saturation in HLS space.
    function shade(color, f) {
        const k = Qt.color(color);
        const r = k.r, g = k.g, b = k.b;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h = 0, s = 0, l = (max + min) / 2;
        if (max !== min) {
            const d = max - min;
            s = l <= 0.5 ? d / (max + min) : d / (2 - max - min);
            if (r === max) h = (g - b) / d;
            else if (g === max) h = 2 + (b - r) / d;
            else h = 4 + (r - g) / d;
            h *= 60;
            if (h < 0) h += 360;
        }
        l = Math.min(1, Math.max(0, l * f));
        s = Math.min(1, Math.max(0, s * f));
        return Qt.hsla(h / 360, s, l, k.a);
    }

    function alpha(color, a) {
        const k = Qt.color(color);
        return Qt.rgba(k.r, k.g, k.b, k.a * a);
    }

    function mix(a, b, t) {
        const x = Qt.color(a), y = Qt.color(b);
        return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t);
    }

    FileView {
        id: css
        path: Quickshell.env("HOME") + "/.config/waybar/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = {};
            const re = /@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})/g;
            let m;
            while ((m = re.exec(text())) !== null) out[m[1]] = m[2];
            root.col = out;
        }
    }
}
