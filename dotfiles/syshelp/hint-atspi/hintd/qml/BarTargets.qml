pragma Singleton

import QtQuick

// Clickable bar items, for the hint overlay (SUPER+D): each registers its MouseArea,
// the overlay asks for screen rectangles. Holds only live items; they leave on destruction.
// One bar is assumed (the window's screen is not readable from an item): `screenName`
// is the screen the registered bar sits on.
QtObject {
    property var items: []
    property point origin: Qt.point(14, 1)   // bar window margins (left, top) on the screen
    property string screenName: ""

    function add(item) {
        items = items.concat([item]);
    }

    function remove(item) {
        items = items.filter(i => i !== item);
    }

    // [{x, y, w, h}] in screen coordinates of the screen named `name`
    function rects(name) {
        const out = [];
        if (name !== screenName)
            return out;
        for (const it of items) {
            if (!it.visible || it.width < 6 || it.height < 6)
                continue;
            const p = it.mapToItem(null, 0, 0);
            out.push({ x: Math.round(p.x + origin.x), y: Math.round(p.y + origin.y), w: Math.round(it.width), h: Math.round(it.height) });
        }
        return out;
    }
}
