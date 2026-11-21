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

    function luma(k) {
        return 0.2126 * k.r + 0.7152 * k.g + 0.0722 * k.b;
    }

    function flowTarget() {
        return eyeY;
    }

    function toLin(v) {
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }

    function fromLin(v) {
        return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
    }

    // equal brightness to the EYE: hue and saturation kept, then in linear light a too-dark color
    // (blue, purple) is lifted toward white and a too-bright one (yellow, green) is scaled down to
    // the same relative luminance. 0.5 ~ CIE lightness 76.
    readonly property real eyeY: 0.5

    // Light desktop: base color is light. Then "white" things become dark ink.
    readonly property bool isLight: luma(Qt.color(c("base"))) > 0.55
    readonly property color ink: isLight ? "#2a2a2e" : "white"
    // Swap a dark-theme hex color (#RRGGBB or #AARRGGBB) for its light twin: invert the channels, keep alpha.
    function sw(h) {
        if (!isLight || h.length < 7) return h;
        const a = h.length === 9 ? h.slice(1, 3) : "", rgb = h.slice(h.length - 6);
        let o = "";
        for (let i = 0; i < 6; i += 2) o += (255 - parseInt(rgb.slice(i, i + 2), 16)).toString(16).padStart(2, "0");
        return "#" + a + o;
    }
    function tint(a) { return isLight ? Qt.rgba(0, 0, 0, a) : Qt.rgba(1, 1, 1, a); }

    // true: every module is plain white (alpha kept, so dimmed states still dim)
    readonly property bool allWhite: true

    function normalize(color, target) {
        if (allWhite) return Qt.rgba(ink.r, ink.g, ink.b, Qt.color(color).a);
        let k = Qt.color(color);
        if (k.hsvHue >= 0) k = Qt.hsva(k.hsvHue, k.hsvSaturation, 1, k.a);
        const r = toLin(k.r), g = toLin(k.g), b = toLin(k.b);
        const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        if (y < 0.001) return Qt.rgba(eyeY, eyeY, eyeY, k.a);
        let o;
        if (y > eyeY) {
            const f = eyeY / y;
            o = [r * f, g * f, b * f];
        } else {
            const t = (eyeY - y) / (1 - y);
            o = [r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t];
        }
        return Qt.rgba(fromLin(o[0]), fromLin(o[1]), fromLin(o[2]), k.a);
    }

    // the flow-1..flow-12 gradient sampled at t (0 = left edge of the screen, 1 = right edge), brightness-normalized
    function flowAt(t) {
        const k = Math.max(0, Math.min(1, t)) * 11;
        const i = Math.min(10, Math.floor(k));
        const m = Qt.color(mix(c("flow-" + (i + 1)), c("flow-" + (i + 2)), k - i));
        // the gradient passes through a washed-out middle; keep it colorful
        return normalize(m.hsvHue < 0 ? m : Qt.hsva(m.hsvHue, Math.max(m.hsvSaturation, 0.6), 1, 1), 0);
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
            root.applyPalette(out);
        }
    }

    // Fade between palettes instead of snapping: the first load is instant,
    // every later change blends old -> new over fadeMs (the whole wallpaper transition).
    property int fadeMs: 10000   // = TRANSITION_DURATION of switch-random-wallpaper.sh
    property var _from: ({})
    property var _to: ({})
    property real _t: 1
    property int _dur: 10000

    function applyPalette(next) {
        if (!next || Object.keys(next).length === 0)
            return;   // empty / half-written colors.css: keep the current palette
        if (JSON.stringify(next) === JSON.stringify(_to))
            return;   // same palette written again (the t=50% pass): keep fading
        // dark <-> light flip (the theme switch): a short 1.2 s blend, not the long wallpaper fade
        const flip = Object.keys(col).length > 0 && next.base !== undefined &&
            Math.abs(luma(Qt.color(next.base)) - luma(Qt.color(c("base")))) > 0.4;
        _dur = flip ? 1200 : fadeMs;
        if (Object.keys(col).length === 0) {
            col = next;
            _to = next;
            return;
        }
        fade.stop();
        _from = col;   // start from what is on screen now, even mid-fade
        _to = next;
        _t = 0;
        fade.start();
    }

    on_TChanged: {
        const out = {};
        for (const k in _to)
            out[k] = _from[k] !== undefined ? Qt.color(mix(_from[k], _to[k], _t)).toString() : _to[k];
        col = out;
    }

    NumberAnimation {
        id: fade
        target: root
        property: "_t"
        from: 0
        to: 1
        duration: root._dur
        easing.type: Easing.InOutSine
    }
}
