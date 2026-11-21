.pragma library

// Waybar modules emit Pango markup; Qt's rich text speaks HTML/CSS.
// Translate the span attributes the scripts use and keep spacing intact.

const SIZES = { "xx-small": "60%", "x-small": "70%", "small": "83%", "medium": "100%",
                "large": "120%", "x-large": "144%", "xx-large": "173%" };

function spanStyle(attrs) {
    const css = [];
    const re = /(\w+)\s*=\s*(['"])(.*?)\2/g;
    let m;
    while ((m = re.exec(attrs)) !== null) {
        const k = m[1], v = m[3];
        if (k === "color" || k === "foreground" || k === "fgcolor") css.push("color:" + v);
        else if (k === "background" || k === "bgcolor") css.push("background-color:" + v);
        else if (k === "font_family" || k === "face" || k === "font") css.push("font-family:'" + v + "'");
        else if (k === "weight" || k === "font_weight") css.push("font-weight:" + (v === "heavy" || v === "ultrabold" ? "bold" : v));
        else if (k === "style" || k === "font_style") css.push("font-style:" + v);
        else if (k === "underline" && v !== "none") css.push("text-decoration:underline");
        else if (k === "size" || k === "font_size") {
            if (SIZES[v]) css.push("font-size:" + SIZES[v]);
            else if (/^\d+$/.test(v)) css.push("font-size:" + (parseInt(v) / 1024) + "pt");
            else css.push("font-size:" + v);
        }
    }
    return '<span style="' + css.join(";") + '">';
}

function toHtml(s) {
    if (!s) return "";
    let out = "";
    const re = /<[^>]*>|[^<]+/g;
    let m;
    while ((m = re.exec(s)) !== null) {
        const t = m[0];
        if (t[0] === "<") {
            const sp = /^<span\b([^]*)>$/.exec(t);
            out += sp ? spanStyle(sp[1]) : t;
        } else {
            out += t.replace(/\t/g, "    ").replace(/ /g, "&nbsp;").replace(/\n/g, "<br>");
        }
    }
    return out;
}


// Rich text collapses runs of spaces; waybar labels keep them.
function spaces(s) {
    return s.replace(/<[^>]*>|[^<]+/g, t => t[0] === "<" ? t : t.replace(/ /g, "&nbsp;"));
}


// Label text for chips: markup and icon-font glyphs removed, entities escaped.
function plain(s) {
    return (s || "").replace(/<[^>]*>/g, "").replace(/[\ue000-\uf8ff]|[\udb80-\udbff][\udc00-\udfff]/g, "")
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\s+/g, " ").trim();
}
