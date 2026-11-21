import QtQuick

// One half-circle-ended pill holding a row of modules.
Rectangle {
    id: cap
    default property alias content: capRow.data
    property int spacing: 2

    // bar hidden: a chip that unhides itself calls peek(chip). The pill comes up for 6 s and
    // shows only the chips that asked (all other items are held invisible, so the pill shrinks).
    readonly property bool isCap: true
    property bool barShown: true
    property bool peeking: false
    property var peeked: []
    property var holds: []   // one persistent Binding per item; `when` switches it (destroying one
                             // while making another on the same item loses the original visible)
    function release() {
        for (const h of holds) h.when = false;
    }
    function sync() {
        const hold = !barShown && peeked.length > 0;
        for (const h of holds) h.when = false;
        if (!hold) return;
        for (const k of capRow.children) {
            if (peeked.indexOf(k) >= 0) continue;
            let h = null;
            for (const x of holds) if (x.target === k) { h = x; break; }
            if (!h) {
                h = holdC.createObject(cap, { target: k, when: false });
                holds.push(h);
            }
            h.when = true;
        }
    }
    Component {
        id: holdC
        Binding { property: "visible"; value: false }
    }
    function peek(item) {
        let k = item;
        while (k && k.parent !== capRow) k = k.parent;
        if (k && !barShown && peeked.indexOf(k) < 0) {
            peeked = peeked.concat([k]);
            sync();
        }
        peeking = true;
        peekTimer.restart();
    }
    onBarShownChanged: { peeked = []; sync(); }
    Timer {
        id: peekTimer
        interval: 6000
        onTriggered: {
            cap.peeking = false;
            cap.peeked = [];
            cap.release();
        }
    }
    visible: barShown || peeking

    y: 4
    height: 22
    radius: 11
    color: Theme.c("base")
    width: capRow.width + 10

    Row {
        id: capRow
        x: 5
        height: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: cap.spacing
    }

    // ---- drag to reorder (Chip calls dragStart/dragMove/dragEnd) ----
    // capName: key in Layout.map. others: the other pills of the same bar (chips can move into them).
    property string capName: ""
    property var others: []
    property Item dragItem: null
    readonly property var all: [cap].concat(others)

    function dragStart(item) {
        dragItem = item;
    }

    // p: pointer in window coordinates. The chip goes to the nearest pill, at the pointer's slot.
    function dragMove(item, p) {
        let best = null, bestD = 1e9;
        for (const c of all) {
            const r = c.mapToItem(null, 0, 0);
            const d = p.x < r.x ? r.x - p.x : p.x > r.x + c.width ? p.x - r.x - c.width : 0;
            if (d < bestD) { bestD = d; best = c; }
        }
        best.place(item, best.row.mapFromItem(null, p.x, p.y).x);
    }

    function dragEnd(item) {
        dragItem = null;
        const m = Object.assign({}, Layout.map);
        for (const c of all)
            if (c.capName !== "") m[c.capName] = c.keys();
        Layout.save(m);
    }

    property alias row: capRow

    // hidden holder: QML cannot call stackBefore, so items are reordered by
    // moving them out here and back (re-adding appends them at the end)
    // (opacity, not visible: an invisible parent would drop the dragged chip's mouse grab)
    Item { id: stash; width: 0; height: 0; opacity: 0 }

    // make capRow's children exactly `res` (all of them, in this order). Returns the moved items.
    function setOrder(res) {
        const cur = Array.from(capRow.children);
        let i = 0;
        while (i < res.length && cur[i] === res[i]) i++;
        if (i >= res.length && cur.length === res.length) return [];
        const tail = res.slice(i);
        for (const k of cur.slice(i)) k.parent = stash;
        for (const k of tail) k.parent = capRow;
        capRow.forceLayout();
        return tail;
    }

    // put item into this pill so that it sits under x (row coordinates)
    function place(item, x) {
        const rest = Array.from(capRow.children).filter(k => k !== item);
        let at = rest.length;
        for (let i = 0; i < rest.length; i++) {
            const k = rest[i];
            if (!k.visible || k.width <= 0) continue;
            if (x < k.x + k.width / 2) { at = i; break; }
        }
        rest.splice(at, 0, item);
        setOrder(rest);
    }

    function keys() {
        const r = [];
        for (const k of capRow.children)
            if (k.objectName !== "") r.push(k.objectName);
        return r;
    }

    // restore the saved order. Items not in the saved lists (new modules) keep their slot.
    function applyLayout() {
        const want = Layout.map[capName];
        if (!want || dragItem) return;
        const find = key => {
            for (const c of all)
                for (const k of c.row.children)
                    if (k.objectName === key) return k;
            return null;
        };
        const saved = [];
        for (const key of want) {
            const k = find(key);
            if (k) saved.push(k);
        }
        const cur = Array.from(capRow.children);
        const res = saved.slice();
        cur.forEach((k, i) => { if (saved.indexOf(k) < 0) res.splice(Math.min(i, res.length), 0, k); });
        // a chip moved here before it was ever drawn (bluetooth, battery: they appear at startup,
        // right when this runs) can stay blank on screen; a short hide and show redraws it
        for (const k of setOrder(res))
            if (typeof k.kick === "function") k.kick();
    }
    Component.onCompleted: Qt.callLater(applyLayout)
    Connections {
        target: Layout
        function onMapChanged() { cap.applyLayout(); }
    }
}
