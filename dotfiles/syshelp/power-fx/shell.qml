import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// power-fx: click-through overlay, soft glowing tail that fades out.
// Cursor position comes from `mmsg get cursorpos` (mango compositor), via poll.sh.
// Effects: wal color gradient, speed-reactive width, comet head, sharp tapered tip,
// sparkles shed from the tail end.
ShellRoot {
    id: root

    // ---- tweak here ----
    property int lifeMs: 225        // how long a trail point lives
    property real maxWidth: 8       // tail thickness at the cursor (at medium speed)
    property real sparkleChance: 2      // sparkles per 8 px of cursor travel; 0 = none (was 3.6 per pointer event, then 3)
    property int rippleMs: 550      // click ripple duration
    property int ghostMs: 550      // afterimage: how long the faint ghost of the trail lingers
    property int touchGhostMs: 275   // the touchscreen ghost trail: half as long as the mouse one
    property real dragWidth: 1.7    // trail thickness multiplier while a button is held
    property real wobble: 4         // tail sway in px at the tip; 0 = straight tail
    // bar color names (from ~/.config/waybar/colors.css, same file the bar reads), cursor to tail tip
    property var glowKeys: ["flow-1", "flow-4", "flow-8", "flow-12"]
    property var coreKeys: ["text", "flow-3", "flow-10"]
    // fallback colors if the wal file is missing
    property var glowStops: ["#78aaff", "#a78bff", "#ff8bd0"]
    property var coreStops: ["#dcebff", "#f0e0ff"]
    // --------------------

    property var glowLut: []
    property var coreLut: []

    property bool dragging: false   // a mouse button is held (ptrwatch: d / u)
    property real dragStart: 0
    property real scrollAng: 0      // direction of the last scroll (the head stretches along it)
    property real scrollT: 0
    property int scrolls: 0
    property real popX: 0
    property real popY: 0
    property string popMon: ""
    property int pops: 0            // counts "button released after a drag" events

    property real cx: 0
    property real cy: 0
    property string mon: ""
    property int seq: 0
    // Touchscreen (ptrwatch "T/t/tu" lines): the finger drives the same trail as the cursor.
    property string touchMon: "eDP-1"   // the monitor the touchscreen is built into
    // Fingers 0..9: the latest point of a finger, as a signal for the trails.
    property int tfSeq: 0
    property int tfIdx: 0
    property real tfX: 0
    property real tfY: 0
    property string tfMon: ""
    property bool tfNew: false          // first point of a touch
    property int tfUpSeq: 0
    property int tfUpIdx: 0
    property int tcSeq: 0               // a finger made a tap
    property int tcIdx: 0
    // Power: the effect is active only on AC. On battery nothing is drawn and the
    // helper processes (poll.sh, click) are stopped, so it costs ~nothing.
    property string acPath: "/sys/class/power_supply/AC/online"
    property bool acOnline: false
    property bool usbOnline: false   // USB-C port reports power a moment before AC does
    readonly property bool onAC: acOnline || usbOnline
    property bool usbSeen: false

    FileView {
        id: acFile
        path: root.acPath
        onLoaded: root.acOnline = text().trim() === "1"
        onLoadFailed: root.acOnline = false
    }

    // Hide the real cursor while the effect is up (AC): switches mango's cursor_theme via
    // cursor-hide.sh. Runs one at a time; re-checks when done so quick plug/unplug ends right.
    property bool cursorHidden: false   // what we last asked cursor-hide.sh to do
    Process {
        id: hideProc
        command: [Quickshell.shellDir + "/cursor-hide.sh", root.cursorHidden ? "on" : "off"]
        onExited: root.syncCursor()
    }
    function syncCursor() {
        if (hideProc.running || root.cursorHidden === root.onAC)
            return;
        root.cursorHidden = root.onAC;
        hideProc.running = true;
    }
    // The overlay windows normally exist only on AC. When the charger is pulled while the pet is in
    // front, they stay for 1.3 s so the pet can burst into sparks, then they go.
    property bool overlayOn: false
    signal petBurst(real x, real y)
    function petBurstNow() {
        petBurst(petPx, petPy);
    }
    Timer {
        id: rebuildT
        interval: 300
        onTriggered: root.overlayOn = true
    }
    Timer {
        id: burstEnd
        interval: 1300
        onTriggered: {
            root.overlayOn = root.onAC;
            root.syncCursor();   // the mango reload (cursor back) waits until the burst is over
        }
    }
    onOnACChanged: {
        if (onAC) {
            burstEnd.stop();
            overlayOn = true;
        } else if (fxOn("pet") && !petHide && !petBehind && petFade > 0.3 && petMode !== "arrive") {
            overlayOn = true;
            burstEnd.restart();
            petBurst(petPx, petPy);
            return;
        } else {
            overlayOn = false;
        }
        syncCursor();
        if (onAC && Date.now() - startT > 3000)   // a real plug-in, not the start-up read
            plugDelay.restart();
    }

    Process {
        id: usbProc
        running: true   // once at start, then on every USB-C power event
        command: ["sh", "-c", "cat /sys/class/power_supply/ucsi-source-psy-*/online 2>/dev/null"]
        onStarted: root.usbSeen = false
        onExited: {
            root.usbOnline = root.usbSeen;
            if (root.usbSeen)
                usbExpire.restart();
            else
                usbExpire.stop();
        }
        stdout: SplitParser {
            onRead: data => { if (data.trim() === "1") root.usbSeen = true; }
        }
    }
    // The USB-C reading is only an early hint (AC follows ~0.7 s later). A port that is powering a
    // device ("source") also reads 1 on battery, so after 3 s only AC/online decides.
    Timer {
        id: usbExpire
        interval: 3000
        onTriggered: root.usbOnline = false
    }

    // No polling: this process just sleeps until the kernel reports a power change
    // (plug / unplug / battery update), then re-reads the AC file once.
    Process {
        running: true
        command: ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--subsystem-match=power_supply"]
        stdout: SplitParser {
            onRead: data => {
                if (data.indexOf("(power_supply)") >= 0) {
                    if (data.indexOf("ucsi-source") >= 0 && !usbProc.running)
                        usbProc.running = true;
                    acFile.reload();
                }
            }
        }
    }

    property int clicks: 0
    property real clickX: 0
    property real clickY: 0
    property string clickMon: ""
    property string clickShape: "circle"
    property double holdUntil: 0    // ms: until then the mouse trail ignores pointer moves (a touch hold is walking the pointer)

    // Turn a list of colors into a smooth 24-step ramp (CSS strings).
    function buildLut(stops) {
        var cols = stops.map(function (s) { return Qt.color(s); });
        var n = 24;
        var out = [];
        for (var i = 0; i < n; i++) {
            if (cols.length < 2) {
                out.push("rgb(" + Math.round(cols[0].r * 255) + "," + Math.round(cols[0].g * 255) + "," + Math.round(cols[0].b * 255) + ")");
                continue;
            }
            var f = i / (n - 1) * (cols.length - 1);
            var j = Math.min(cols.length - 2, Math.floor(f));
            var t = f - j;
            var a = cols[j], b = cols[j + 1];
            out.push("rgb(" + Math.round((a.r + (b.r - a.r) * t) * 255) + ","
                     + Math.round((a.g + (b.g - a.g) * t) * 255) + ","
                     + Math.round((a.b + (b.b - a.b) * t) * 255) + ")");
        }
        return out;
    }

    function rebuild() {
        glowLut = buildLut(glowStops);
        coreLut = buildLut(coreStops);
    }

    Component.onCompleted: {
        rebuild();
        var names = [];
        for (var si = 0; si < Quickshell.screens.length; si++)
            names.push(Quickshell.screens[si].name);
        knownScreens = names;
        if (petOn)
            petSpawn();   // start-up on AC: the pet flies in
    }

    // Colors come from the bar palette file. Reloads by itself when the theme is re-applied.
    FileView {
        path: Quickshell.env("HOME") + "/.config/waybar/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var col = {};
            var re = /@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})/g;
            var m;
            while ((m = re.exec(text())) !== null) col[m[1]] = m[2];
            var pick = function (key) { return col[key]; };
            var g = root.glowKeys.map(pick).filter(function (c) { return !!c; });
            var c = root.coreKeys.map(pick).filter(function (c) { return !!c; });
            if (g.length > 0) root.glowStops = g;
            if (c.length > 0) root.coreStops = c;
            root.rebuild();
        }
    }

    // ptrwatch (C++, see ptrwatch.cpp): event-driven, so it uses no CPU while the mouse is
    // still. It prints "c" for a click/tap, and the cursor position as a JSON line while
    // the pointer moves (and once after a focus change). Runs only on AC.
    Process {
        running: root.onAC
        onRunningChanged: if (!running) root.dragging = false
        command: [Quickshell.shellDir + "/ptrwatch"]
        stdout: SplitParser {
            onRead: data => {
                if (data === "k") {   // a key was pressed: mango does not stream tile resizes, so look once
                    root.petKey();    // the pet rushes to the typing spot
                    return;
                }
                if (data === "K") {   // later look: the keys may be slow to act; also the tiles (resize)
                    root.petKey();
                    if (!snapProc.running)
                        snapProc.running = true;
                    return;
                }
                if (data.charAt(0) === "s") {   // "s DX DY": scrolling
                    var sv = data.split(" ");
                    var sdx = parseInt(sv[1]);
                    var sdy = parseInt(sv[2]);
                    if (!isNaN(sdx) && !isNaN(sdy) && (sdx !== 0 || sdy !== 0)) {
                        root.scrollAng = Math.atan2(sdy, sdx);
                        root.scrollT = Date.now();
                        root.scrolls++;
                    }
                    return;
                }
                if (data.charAt(0) === "T" || data.charAt(0) === "t") {
                    // Touchscreen, one line per finger N (slot 0..9):
                    //   "T N U V" first point of a touch, "t N U V" later ones (U, V = 0..10000 of the panel),
                    //   "tu N" finger N lifted, "tc N" finger N made a tap (finger 0's tap is a plain "c").
                    if (!root.fxOn("touchtrail"))
                        return;
                    var tv = data.split(" ");
                    var tn = parseInt(tv[1]);
                    var tsc = null;
                    for (var si = 0; si < Quickshell.screens.length; si++)
                        if (Quickshell.screens[si].name === root.touchMon)
                            tsc = Quickshell.screens[si];
                    // A rotated screen is skipped: the touch axes no longer match the output.
                    if (!tsc || isNaN(tn) || tsc.height > tsc.width)
                        return;
                    if (tv[0] === "tu") {
                        root.tfUpIdx = tn;
                        root.tfUpSeq++;
                        return;
                    }
                    if (tv[0] === "tc") {   // a tap: a ripple where finger N touched
                        root.tcIdx = tn;
                        root.tcSeq++;
                        return;
                    }
                    var tu = parseInt(tv[2]);
                    var tw = parseInt(tv[3]);
                    if (isNaN(tu) || isNaN(tw))
                        return;
                    // Every finger (0..9) has its own ghost-only trail in the screen's `ext` list.
                    // The mouse cursor state (cx, cy, seq, head, ring) is not touched.
                    root.tfIdx = tn;
                    root.tfX = tsc.x + tu / 10000 * tsc.width;
                    root.tfY = tsc.y + tw / 10000 * tsc.height;
                    root.tfMon = tsc.name;
                    root.tfNew = tv[0] === "T";
                    root.tfSeq++;
                    return;
                }
                if (data === "d") {
                    root.dragging = true;
                    root.dragStart = Date.now();
                    return;
                }
                if (data === "u") {
                    if (root.dragging && Date.now() - root.dragStart > 250) {   // a real drag, not a click
                        root.popX = root.cx;
                        root.popY = root.cy;
                        root.popMon = root.mon;
                        root.pops++;
                    }
                    root.dragging = false;
                    return;
                }
                if (data === "c" || data === "cr" || data === "cm") {
                    root.clickShape = data === "cr" ? "square" : (data === "cm" ? "tri" : "circle");
                    root.clickX = root.cx;
                    root.clickY = root.cy;
                    root.clickMon = root.mon;
                    root.clicks++;
                    return;
                }
                try {
                    var o = JSON.parse(data);
                    root.cx = o.x;
                    root.cy = o.y;
                    root.mon = o.monitor;
                    root.seq++;
                } catch (e) {}
            }
        }
    }


    Process {
        id: snapProc
        command: ["mmsg", "get", "all-clients"]
        stdout: SplitParser {
            onRead: data => root.onClients(data)
        }
    }

    // ---- Tile effects: focus pulse, open/close burst, move echo ----
    // Fed by `mmsg watch all-clients` (one line per change). Runs only on AC, inside this same
    // quickshell process (no extra process).
    property var fxList: []          // active tile effects, shared by all screens
    property int fxSeq: 0            // bumps when the list changes
    property var prevClients: ({})
    property bool clientsInit: false

    Process {
        running: root.onAC
        command: ["mmsg", "watch", "all-clients"]
        stdout: SplitParser {
            onRead: data => root.onClients(data)
        }
        onRunningChanged: if (!running) {
            root.clientsInit = false;
            root.prevClients = ({});
            root.fxList = [];
        }
    }

    // ---- Screen-wide and attention effects ----
    //  keymode tint: screen edges tinted while mango is in a special key mode (cursor mode etc.)
    //  plug-in pulse: when the charger is plugged in, lights run from the bottom-left corner around the edges
    //  urgent tile: a tile that wants attention breathes a soft red edge
    //  focus hop: a short glowing arc from the previously focused tile to the newly focused one
    property real startT: Date.now()
    property string lastFocId: ""

    Timer {
        id: urgDemo
        onTriggered: {
            for (var i = 0; i < root.fxList.length; i++)
                if (root.fxList[i].fake)
                    root.fxEnd(root.fxList[i]);
        }
    }

    Timer {
        id: plugDelay
        interval: 1  // no wait: the windows are created at the same moment
        onTriggered: root.fxPlug()
    }

    // ---- Desktop pet: a second comet (same drawing as the cursor, no sparkles) that jerks around like an
    // eye, floats around the focused window, keeps away from the cursor, rushes to where you last clicked
    // while you type (and snaps away when the mouse moves), flies in from the bottom-left on plug-in and
    // goes to look at new notifications. Switch: `pet` in effects.conf. Runs only on AC (the windows
    // that draw it exist only on AC, and petTick stops with petOn). ----
    property bool petOn: onAC && fxOn("pet")
    property real petX: -500            // global compositor coordinates
    property real petY: -500
    property real petV: 0               // speed, px/ms (smoothed)
    property real petTx: 0              // current target
    property real petTy: 0
    property string petMode: "arrive"   // arrive | idle | type | flee | curious | hide | poke
    // `annoying`: poke = click a thing that hintd found near the pet
    property double petPokeNext: 0
    property double petPokeAt: 0
    property string petPokePhase: "go"  // go | hold | after
    property string petPokeMon: ""
    property int petPokeLx: 0           // click spot, monitor-local (what hintd wants)
    property int petPokeLy: 0
    property real petPokeX: 0           // click spot, global (where the pet flies)
    property real petPokeY: 0
    property string petPokeFoc: ""      // focused window when the list was read; a change cancels the click
    property var petPokeLines: []
    property int petPokeCand: -1
    property int petPokeAsked: 0
    // moods: read (scrolling), sleep (5 min idle), urgent (circle the urgent tile), dare (cursor still)
    property double petActT: 0          // last keyboard, mouse or scroll activity
    property double petMoveT: 0         // last time the cursor moved
    property real petLCx: 0
    property real petLCy: 0
    property int petLClicks: 0
    property bool petDared: false       // one dare per still period of the cursor
    property real petDim: 1             // 0.35 while asleep
    property var petUrgId: ""
    property real petFreezeX: 0
    property real petFreezeY: 0
    // tricks (every 1-3 min of idle), exploring a new screen, perching on a floating window
    property double petNextTrick: 0
    property string petTrickKind: "loop"   // loop | eight | zoom
    property double petTrickT0: 0
    // ripples: a ring in the pet's colour where it lands, when a trick starts or ends, and when you click
    signal petRing(real x, real y, real sz, int dur)
    function petRipple(sz) {
        if (petOn && !petHide)
            petRing(petPx, petPy, sz, 900);
    }
    property real petDareT: 0        // when the pet settled next to the cursor (0 = not yet)
    property int petDareStage: 0
    property real petAnswerAt: 0
    property bool petPerchRang: false
    property bool petSleepRang: false
    property bool petTrickRang: false
    property real petTrickOX: 0            // leftover distance to the start of the shape, eased out over 250 ms
    property real petTrickOY: 0
    property bool petTrickGo: false        // false while the pet is still flying to the start of the shape
    property var petTrickM: null           // the screen the trick is drawn on: the shape is kept inside it
    property string petTrickForce: ""      // preview: choose the trick
    property real petTrickCycle: 0         // ms one round of the shape takes (0 = the shape is not repeated); the swarm spreads over one round
    property real petTrickDur: 1800
    property real petTrickS0: 0
    property real petTrickLen: 0
    property real petLife: 450             // trail lifetime of the pet, ms: grows while it draws a trick shape
    property var petDvd: null              // dvd trick: the box it bounces in {x0, y0, x1, y1} and the speed {vx, vy} in px/s
    property real petTrickCX: 0
    property real petTrickCY: 0
    property real petTrickH: 0
    property string petLapMon: ""          // "" = the cursor's screen (hourly lap); else a screen just plugged in
    property real petLapSpd: 0.5           // px/ms along the outline
    property bool monsInit: false
    property var petPerchId: ""
    function petNewScreen(name) {
        if (!petOn || petMode === "hide" || petMode === "arrive")
            return;
        petLapMon = name;
        petLapSpd = 0.35;
        petGo("lap");
    }
    function petPerch(n) {
        if (!petOn || !(petMode === "idle" || petMode === "peek" || petMode === "dare" || petMode === "curious"))
            return;
        petPerchId = n.id;
        petGo("perch");
    }
    function petLapRect() {
        var lm = prevMons[petLapMon !== "" ? petLapMon : mon];
        return lm ? { x: lm.x, y: lm.y, w: lm.w, h: lm.h } : null;
    }
    property double petHopT: 0         // last key: the hop
    property double petDragSince: 0
    property int petLapHour: -1
    property double petLapT0: 0
    property double petStartleT: 0
    property double petSCt: 0
    property real petSCx: 0
    property real petSCy: 0
    property int petPeekClicks: 0
    property int petSlpC: 0            // sleep corner of the tile: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
    // a window became urgent: fly over and circle that tile until it is no longer urgent
    function petUrgent(n) {
        if (!petOn || petMode === "hide" || petMode === "arrive")
            return;
        petUrgId = n.id;
        petGo("urgent");
    }
    function petPokeAsk() {
        petPokeLines = [];
        petPokeAsked++;
        petPokeFoc = lastFocId;
        petPokeQ.running = true;
    }
    // first line = monitor name, then one "x y w h" per line (monitor-local). Pick a small thing near the pet.
    function petPokePick() {
        var L = petPokeLines;
        if (L.length < 2 || petMode !== "idle" || lastFocId !== petPokeFoc)
            return;
        var m = prevMons[L[0]];
        if (!m)
            return;
        var c = [];
        for (var i = 1; i < L.length; i++) {
            var p = L[i].split(" ");
            if (p.length < 4)
                continue;
            var bx = +p[0], by = +p[1], bw = +p[2], bh = +p[3];
            if (!(bw >= 10 && bh >= 10 && bw <= 400 && bh <= 200))
                continue;
            var gx = m.x + bx + bw / 2, gy = m.y + by + bh / 2;
            var dp = Math.hypot(gx - petPx, gy - petPy);
            if (dp < 40 || dp > 500 || Math.hypot(gx - cx, gy - cy) < root.petAvoid * 1.5)
                continue;
            c.push({ gx: gx, gy: gy, lx: Math.round(bx + bw / 2), ly: Math.round(by + bh / 2), d: dp });
        }
        petPokeCand = c.length;
        if (c.length === 0)
            return;
        c.sort(function (u, v) { return u.d - v.d; });
        var t = c[Math.floor(Math.random() * Math.min(5, c.length))];
        petPokeMon = L[0];
        petPokeLx = t.lx;
        petPokeLy = t.ly;
        petPokeX = t.gx;
        petPokeY = t.gy;
        petGo("poke");
    }
    property double petModeT: 0
    property double petLast: 0
    property double petPendAt: 0        // when the waiting mode change happens
    property string petPending: ""      // the mode it will change to ("" = none)
    property double petRelocT: 0
    property bool petBehind: false      // drawn under the windows (hiding) instead of over them
    property real petFade: 1            // 0..1: fades out while it slips under a tile, and back in when it comes out
    property real petAnnoy: 0           // ms of the cursor bothering it; at 7 s it goes to hide
    property double petHideUntil: 0
    property string petHidePhase: ""    // gap (go to the gap) | under (hidden) | out (back to the gap)
    property string petAfter: ""        // the mode to take after coming out
    property string petCurPhase: "go"   // curious: go (flying to the notifications) | look (hovering there)
    property double petLookT: 0
    property real petHead: -0.8        // direction of travel, radians
    property real petTurnR: 70          // minimum turning radius at speed, px
    property real petRunDX: 1          // direction of the dash into the gap (unit vector)
    property real petRunDY: 0
    property real petSlide: 0           // px still to travel under the tile after the gap
    property real petGapX: 0
    property real petGapY: 0
    property real petUnderX: 0
    property real petUnderY: 0
    property double petBounceT: 0
    property double petKeyT: 0          // last key press
    property real petS: 0               // position along the window outline, px
    property real petJtx: 0             // where the eye shift is heading
    property real petJty: 0
    property real petJx: 0              // current eye shift
    property real petJy: 0
    property real petAng: 0             // orbit angle while typing / curious
    property real petCurX: 0            // where the cursor was when typing began
    property real petCurY: 0
    property bool petHide: false        // the focused tile is fullscreen
    property int petSeq: 0              // bumps every frame; the windows listen
    property real petAvoid: 170   // keeps this far from the cursor
    property real petPx: -500           // the smooth (spring) position; petX/petY add the tiny eye jitter
    property real petPy: -500
    property real petVx: 0              // spring velocity, px/s
    property real petVy: 0
    property real petSv: 30             // drift speed along the outline, px/s
    property real petW: 3               // current spring stiffness (eased between modes)
    property real petPh1: 0             // random phases for the irregular float
    property real petPh2: 0
    property double petNextJit: 0
    property int swarmCount: 7         // swarm look: how many fireflies (restart to apply)
    property real petSize: 0.55         // pet size compared with the cursor comet
    // the pet's colors: the cursor's colors turned around the color wheel, so the two are easy to tell apart
    property var petGlowLut: hueShift(glowLut, 0.5)
    property var petCoreLut: hueShift(coreLut, 0.5)

    // ---- Swarm drawing, shared by the pet and the wild swarms ----
    // Draws the lights fl ({x, y}, shifted by -ox/-oy into the canvas) as soft glows. tint: glow colour "rgb(r,g,b)".
    // mk/ma: mood colour (red, green or blue) and how strongly it is on (0..1), steady, no flashing.
    // mixTint/mixA: a second swarm's colour that this one is blending toward during a merge (mixA 0 = off).
    // alpha: overall opacity (the pet gets its opacity from its view, so it passes 1).
    function drawLights(ctx, fl, tint, mk, ma, mixTint, mixA, core, now, ox, oy, alpha) {
        var t = now / 1000;
        var mix = 0, gT = [0, 0, 0], cT = [0, 0, 0];
        var tc = tint.match(/\d+/g);
        var tr = tc ? Number(tc[0]) : 255, tg = tc ? Number(tc[1]) : 200, tb = tc ? Number(tc[2]) : 100;
        if (mixA > 0.01 && mixTint) {
            var mc = mixTint.match(/\d+/g);
            if (mc) {
                tr += (Number(mc[0]) - tr) * 0.5 * mixA;
                tg += (Number(mc[1]) - tg) * 0.5 * mixA;
                tb += (Number(mc[2]) - tb) * 0.5 * mixA;
            }
        }
        if (ma > 0.01) {
            mix = ma;   // steady colour, fades in and out
            gT = mk === "red" ? [255, 40, 30] : (mk === "green" ? [50, 220, 90] : [60, 130, 255]);
            cT = mk === "red" ? [255, 120, 100] : (mk === "green" ? [150, 255, 170] : [150, 200, 255]);
        }
        var gr = Math.round(tr + (gT[0] - tr) * mix), gg = Math.round(tg + (gT[1] - tg) * mix), gb = Math.round(tb + (gT[2] - tb) * mix);
        var kr = Math.round(255 + (cT[0] - 255) * mix), kg = Math.round(248 + (cT[1] - 248) * mix), kb = Math.round(225 + (cT[2] - 225) * mix);
        var gc = "rgba(" + gr + "," + gg + "," + gb + ",";
        var kc = "rgba(" + kr + "," + kg + "," + kb + ",";
        ctx.globalAlpha = alpha;
        ctx.globalCompositeOperation = "lighter";
        for (var j = 0; j < fl.length; j++) {
            var f = fl[j];
            var fx = f.x - ox, fy = f.y - oy;
            var a = 0.65 + 0.35 * Math.sin(t * (5 + j) + j);
            if (core) {
                var cr = j === 0 ? 5.5 : 4.5;   // the leader is a little bigger
                var cg = ctx.createRadialGradient(fx, fy, 0, fx, fy, cr);
                cg.addColorStop(0, kc + (0.95 * a) + ")");
                cg.addColorStop(1, kc + "0)");
                ctx.fillStyle = cg;
                ctx.beginPath();
                ctx.arc(fx, fy, cr, 0, Math.PI * 2);
                ctx.fill();
            } else {
                var hg = ctx.createRadialGradient(fx, fy, 0, fx, fy, 16);
                hg.addColorStop(0, gc + Math.min(1, (0.9 + 0.3 * mix) * a) + ")");
                hg.addColorStop(1, gc + "0)");
                ctx.fillStyle = hg;
                ctx.beginPath();
                ctx.arc(fx, fy, 16, 0, Math.PI * 2);
                ctx.fill();
            }
        }
        ctx.globalCompositeOperation = "source-over";
        ctx.globalAlpha = 1;
    }
    property string petMixTint: ""   // merge: the other swarm's glow colour (the pet blends toward it)
    property real petMixA: 0         // merge: how far the pet is blended (0 = not merging)

    function hueShift(lut, dh) {
        var out = [];
        for (var i = 0; i < lut.length; i++) {
            var mt = /rgb\((\d+),(\d+),(\d+)\)/.exec(lut[i]);
            if (!mt) { out.push(lut[i]); continue; }
            var r = mt[1] / 255, g = mt[2] / 255, b = mt[3] / 255;
            var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
            var l = (mx + mn) / 2, h = 0, s = 0, d = mx - mn;
            if (d > 0) {
                s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
                if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
                else if (mx === g) h = (b - r) / d + 2;
                else h = (r - g) / d + 4;
                h /= 6;
            }
            h = (h + dh) % 1;
            var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
            var ch = function (t) {
                t = (t + 1) % 1;
                if (t < 1 / 6) return p + (q - p) * 6 * t;
                if (t < 1 / 2) return q;
                if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
                return p;
            };
            out.push("rgb(" + Math.round(ch(h + 1 / 3) * 255) + "," + Math.round(ch(h) * 255) + "," + Math.round(ch(h - 1 / 3) * 255) + ")");
        }
        return out;
    }

    onPetOnChanged: {
        if (petOn)
            petSpawn();
    }

    // 0.3 (night) .. 1 (morning), straight lines between the points
    function petEnergy() {
        var d = new Date();
        var h = d.getHours() + d.getMinutes() / 60;
        var T = [[0, 0.3], [5, 0.3], [8, 1.0], [17, 0.9], [21, 0.5], [24, 0.3]];
        for (var i = 1; i < T.length; i++)
            if (h <= T[i][0])
                return T[i - 1][1] + (T[i][1] - T[i - 1][1]) * (h - T[i - 1][0]) / (T[i][0] - T[i - 1][0]);
        return 0.3;
    }

    // the rectangle the pet floats around: the focused tile, else the cursor's screen
    // DVD bounce: a box (the tile, 24 px in) and a diagonal speed. dvdAt(d, t) = where the logo is t seconds after the start.
    function dvdMake(a, x, y, seed) {
        var x0 = a.x + 24, y0 = a.y + 24, x1 = a.x + a.w - 24, y1 = a.y + a.h - 24;
        if (x1 - x0 < 100) { x0 = a.x; x1 = a.x + a.w; }
        if (y1 - y0 < 100) { y0 = a.y; y1 = a.y + a.h; }
        var ang = 0.55 + Math.random() * 0.5;   // 31..60 deg off the horizontal: never a straight line
        var sx = Math.random() < 0.5 ? -1 : 1, sy = Math.random() < 0.5 ? -1 : 1;
        var sp = 400;
        return { x0: x0, y0: y0, x1: x1, y1: y1, px: Math.max(x0, Math.min(x1, x)), py: Math.max(y0, Math.min(y1, y)),
                 vx: sx * sp * Math.cos(ang), vy: sy * sp * Math.sin(ang) };
    }
    function dvdFold(p0, v, t, lo, hi) {   // position after t s, bouncing between lo and hi
        var L = hi - lo, m = (((p0 - lo) + v * t) % (2 * L) + 2 * L) % (2 * L);
        return lo + (m < L ? m : 2 * L - m);
    }
    function dvdAt(d, t) {
        return { x: dvdFold(d.px, d.vx, t, d.x0, d.x1), y: dvdFold(d.py, d.vy, t, d.y0, d.y1) };
    }

    function petArea() {
        var f = prevClients[lastFocId];
        if (f && f.vis && f.foc && !f.fs && f.w > 120 && f.h > 120)
            return { x: f.x, y: f.y, w: f.w, h: f.h, tile: true };
        var m = prevMons[mon];
        if (!m && Quickshell.screens.length > 0) {
            var s = Quickshell.screens[0];
            m = { x: s.x, y: s.y, w: s.width, h: s.height };
        }
        return m ? { x: m.x + 40, y: m.y + 40, w: m.w - 80, h: m.h - 80 } : null;
    }

    // point s px along the outline of rect a, inset 14 px so the pet stays on screen; .P = outline length
    function petPerim(a, s) {
        var x = a.x + 14, y = a.y + 14, w = a.w - 28, h = a.h - 28;
        var r = Math.max(4, Math.min(24, w / 4, h / 4));
        var P = 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math.PI * r;
        var p = perimPoint(x, y, w, h, r, ((s % P) + P) % P);
        p.P = P;
        return p;
    }

    function petOnScreen(x, y) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var s = Quickshell.screens[i];
            if (x >= s.x + 8 && y >= s.y + 8 && x <= s.x + s.width - 8 && y <= s.y + s.height - 8)
                return true;
        }
        return false;
    }

    // Flying in from the bottom-left corner of the leftmost screen.
    function petSpawn() {
        var s = null;
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (!s || Quickshell.screens[i].x < s.x)
                s = Quickshell.screens[i];
        if (!s)
            return;
        petX = s.x - 60;
        petY = s.y + s.height + 60;
        petPx = petX;
        petPy = petY;
        petVx = 0;
        petVy = 0;
        petHead = -0.8;
        petSv = 30;
        petW = 3;
        petPh1 = Math.random() * 6.28;
        petPh2 = Math.random() * 6.28;
        petV = 0;
        petPending = "";
        petBehind = false;
        petFade = 1;
        petAnnoy = 0;
        petMode = "arrive";
        petLast = Date.now();
        petModeT = petLast + Math.random() * 2000;   // waits off-screen for up to 2 s, then flies in
        petS = Math.random() * 1000;
    }

    // Every change of mode waits a random 0-2 s first (petGo asks, petApply does it).
    function petGo(mode) {
        if (petMode === "hide" && petBehind && mode !== "hide") {   // under a tile: first come back out through the gap
            petAfter = mode;
            petHideUntil = 0;
            return;
        }
        if (petPending === mode || (petPending === "" && petMode === mode))
            return;
        petPending = mode;
        petPendAt = Date.now() + Math.random() * 2000;
    }

    function petApply(mode) {
        var now = Date.now();
        petPending = "";
        if (mode !== "hide")
            petBehind = false;
        if (mode === "hide") {
            if (!petFindGap()) {   // no gap between tiles to slip through: stay out
                petAnnoy = 0;
                return;
            }
            petHidePhase = "gap";
            var rdx = petGapX - petPx, rdy = petGapY - petPy;
            var rdl = Math.hypot(rdx, rdy);
            petRunDX = rdl > 1 ? rdx / rdl : 1;   // the dash is along this one straight line
            petRunDY = rdl > 1 ? rdy / rdl : 0;
        } else if (mode === "poke") {
            petPokePhase = "go";
        } else if (mode === "sleep") {
            petSleepRang = false;
            var sa = petArea();
            petSlpC = sa ? ((petPx > sa.x + sa.w / 2 ? 1 : 0) + (petPy > sa.y + sa.h / 2 ? 2 : 0)) : 0;
        } else if (mode === "trick") {
            var tk = ["loop", "eight", "zoom", "slalom", "clover", "pendulum", "tile", "dvd"];
            petTrickKind = tk.indexOf(petTrickForce) >= 0 ? petTrickForce : tk[Math.floor(Math.random() * tk.length)];
            petTrickForce = "";
            petTrickT0 = now;
            petTrickGo = false;
            petTrickRang = false;
            petTrickH = Math.hypot(petVx, petVy) > 30 ? Math.atan2(petVx === 0 && petVy === 0 ? 0 : petVy, petVx) : petHead;
            var ta = petArea();
            petTrickCX = petPx;
            petTrickCY = petPy;
            petTrickDur = 1800;
            petTrickCycle = 0;
            // Every shape is repeated: petTrickCycle is the time one round takes, petTrickDur the whole trick.
            if (petTrickKind === "loop") {   // a circle of 90 px that passes through the pet, in the direction it is heading
                petTrickCX = petPx - 90 * Math.sin(petTrickH);
                petTrickCY = petPy + 90 * Math.cos(petTrickH);
                petTrickCycle = 1600;
                petTrickDur = 4800;   // 3 rounds
            } else if (petTrickKind === "eight") {
                petTrickCycle = 2600;
                petTrickDur = 5200;   // 2 rounds
            } else if (petTrickKind === "slalom" && ta) {   // a weaving run to the far side of the tile
                var sex = 2 * (ta.x + ta.w / 2) - petPx, sey = 2 * (ta.y + ta.h / 2) - petPy;
                if (Math.hypot(sex - petPx, sey - petPy) < 500) {
                    sex = petPx + (petPx < ta.x + ta.w / 2 ? 560 : -560);
                    sey = petPy;
                }
                petTrickH = Math.atan2(sey - petPy, sex - petPx);
                petTrickLen = Math.hypot(sex - petPx, sey - petPy);
                petTrickCycle = Math.max(2000, Math.min(3200, petTrickLen / 0.3));
                petTrickDur = petTrickCycle * 2;   // there and back
            } else if (petTrickKind === "clover") {   // four round petals (circles of 75 px through the middle), the pet starts in the middle
                petTrickCycle = 4800;
                petTrickDur = 9600;   // 2 rounds
            } else if (petTrickKind === "pendulum") {   // swings from a pivot 150 px above, each swing shorter
                petTrickH = (Math.random() < 0.5 ? -1 : 1) * 0.9;   // start angle (rad), side
                petTrickCX = petPx - 150 * Math.sin(petTrickH);
                petTrickCY = petPy - 150 * Math.cos(petTrickH);
                petTrickCycle = 2600;
                petTrickDur = 6500;   // swings die down slower (see the path below)
            } else if (petTrickKind === "tile") {   // two fast laps around the outline of the tile
                petTrickS0 = petS;
                petTrickCycle = ta && ta.tile ? petPerim(ta, 0).P / 0.45 : 6000;
                petTrickDur = petTrickCycle * 2;
            } else if (petTrickKind === "dvd") {   // bounces around the active tile like a DVD logo
                petTrickGo = true;
                petTrickDur = 8000;
                petDvd = dvdMake(ta, petPx, petPy, petTrickH);
            } else if (petTrickKind === "zoom") {
                petTrickGo = true;
            }
            // keep the whole shape on the screen: move the middle of it inward (the pet then flies to the start of the shape)
            petTrickM = null;
            for (var mk in prevMons) {
                var mr = prevMons[mk];
                if (petPx >= mr.x && petPx < mr.x + mr.w && petPy >= mr.y && petPy < mr.y + mr.h)
                    petTrickM = mr;
            }
            if (petTrickM) {
                var fl = 0, fr = 0, fu = 0, fd = 0;   // how far the shape reaches left, right, up, down of its middle
                if (petTrickKind === "loop") { fl = fr = fu = fd = 100; }
                else if (petTrickKind === "eight") { fl = fr = fu = fd = 180; }
                else if (petTrickKind === "clover") { fl = fr = fu = fd = 160; }
                else if (petTrickKind === "pendulum") { fl = fr = 125; fu = -80; fd = 160; }
                if (fl > 0 || fu !== 0) {
                    petTrickCX = Math.max(petTrickM.x + fl + 16, Math.min(petTrickM.x + petTrickM.w - fr - 16, petTrickCX));
                    petTrickCY = Math.max(petTrickM.y + fu + 16, Math.min(petTrickM.y + petTrickM.h - fd - 16, petTrickCY));
                }
            }
        } else if (mode === "perch") {
            petPerchRang = false;
        } else if (mode === "lap") {
            petLapT0 = now;
        } else if (mode === "dare") {
            petDared = true;
            petDareT = 0;
            petDareStage = 0;
        } else if (mode === "curious") {
            petCurPhase = "go";
        } else if (mode === "type") {
            petCurX = cx;
            petCurY = cy;
            petKeyT = Math.max(petKeyT, now - 1000);   // stay still for at least 1.5 s
            petFreezeX = petPx + petVx / 8;   // the spot it glides to, so it stops without going back
            petFreezeY = petPy + petVy / 8;
        } else if (mode === "flee") {
            petFleeTarget();
        }
        petMode = mode;
        petModeT = now;
    }

    // A key was pressed: go and hover near the typing spot (the last click).
    function petKey() {
        if (!petOn)
            return;
        petKeyT = Date.now();
        petActT = petKeyT;   // a key still counts as activity (sleep)
        // typing makes it behave as in a dare: creep up to the cursor and stay near it
        if ((petMode === "idle" || petMode === "peek") && petPending === "")
            petGo("dare");
    }

    // The point of the window outline that is farthest from the cursor becomes the new place to float.
    function petFleeTarget() {
        var a = petArea();
        if (!a)
            return;
        var L = petPerim(a, 0).P;
        var bx = petX, by = petY, bd = -1, bs = petS;
        for (var i = 0; i < 12; i++) {
            var p = petPerim(a, petS + L * i / 12);
            var d = Math.hypot(p.x - cx, p.y - cy);
            if (d > bd) { bd = d; bx = p.x; by = p.y; bs = petS + L * i / 12; }
        }
        petS = bs;   // idle resumes from the new spot, not the old one beside the cursor
        petTx = bx;
        petTy = by;
    }

    function petFlee() {
        petGo("flee");
    }

    // A notification came in: go and look at the notification cards (top-left, under the bar), then come back.
    function petCurious() {
        if (!petOn || petMode === "type")
            return;
        petGo("curious");
    }

    // Looks for the closest gap between two tiles on the focused tile's screen.
    // Sets petGap* (where to switch layers) and petUnder* (the middle of the tile to slip under). false = none.
    function petFindGap() {
        var f = prevClients[lastFocId];
        var tiles = [];
        for (var id in prevClients) {
            var c = prevClients[id];
            if (c.vis && c.w > 60 && c.h > 60 && (!f || c.mon === f.mon))
                tiles.push(c);
        }
        var best = null, bd = -1;
        for (var i = 0; i < tiles.length; i++)
            for (var j = i + 1; j < tiles.length; j++) {
                var g = gapLine(tiles[i], tiles[j]);
                if (!g)
                    continue;
                // the point of this gap that is closest to the pet
                var gdx = g.x2 - g.x1, gdy = g.y2 - g.y1, gl2 = gdx * gdx + gdy * gdy;
                var gt = gl2 > 0 ? Math.max(0.05, Math.min(0.95, ((petPx - g.x1) * gdx + (petPy - g.y1) * gdy) / gl2)) : 0.5;
                var px = g.x1 + gdx * gt, py = g.y1 + gdy * gt;
                var d = Math.hypot(px - petPx, py - petPy);
                if (Math.hypot(px - cx, py - cy) < root.petAvoid * 0.7)
                    d += 100000;   // not a gap right under the cursor, unless there is no other
                if ((px - petPx) * (petPx - cx) + (py - petPy) * (petPy - cy) < 0)
                    d += 50000;    // prefer a gap on the side away from the cursor
                if (bd < 0 || d < bd) { bd = d; best = { x: px, y: py, a: tiles[i], b: tiles[j] }; }
            }
        if (!best)
            return false;
        var ca = Math.hypot(best.a.x + best.a.w / 2 - cx, best.a.y + best.a.h / 2 - cy);
        var cb = Math.hypot(best.b.x + best.b.w / 2 - cx, best.b.y + best.b.h / 2 - cy);
        var u = ca > cb ? best.a : best.b;   // the tile farther from the cursor
        petGapX = best.x;
        petGapY = best.y;
        petUnderX = u.x + u.w / 2;
        petUnderY = u.y + u.h / 2;
        return true;
    }

    // distance from point (qx, qy) to the straight path (ax, ay) -> (bx, by)
    function petSegDist(ax, ay, bx, by, qx, qy) {
        var dx = bx - ax, dy = by - ay;
        var l2 = dx * dx + dy * dy;
        var t = l2 > 0 ? Math.max(0, Math.min(1, ((qx - ax) * dx + (qy - ay) * dy) / l2)) : 0;
        return Math.hypot(ax + dx * t - qx, ay + dy * t - qy);
    }

    // The cursor came near the place where the pet is floating (or across its path): pick another spot on
    // the outline, as near as possible but well clear of the cursor and not behind it.
    function petRelocate(a) {
        var L = petPerim(a, 0).P;
        var R = petAvoid * 1.4;
        var bestS = petS, bestScore = 1e18, far = -1, farS = petS;
        for (var i = 1; i < 24; i++) {
            var s = petS + L * i / 24;
            var p = petPerim(a, s);
            var dc = Math.hypot(p.x - cx, p.y - cy);
            if (dc > far) { far = dc; farS = s; }
            if (dc >= R && petSegDist(petPx, petPy, p.x, p.y, cx, cy) >= petAvoid * 0.9 && i < bestScore) {
                bestScore = i < 12 ? i : 24 - i;   // the fewest steps along the outline, either way round
                bestS = s;
            }
        }
        petS = bestScore < 1e18 ? bestS : farS;
        petSv = 20 * (Math.random() < 0.5 ? -1 : 1);
    }

    function petStep() {
        var now = Date.now();
        var dt = Math.min(60, Math.max(1, now - petLast));
        petLast = now;
        var en = petEnergy();
        var f = prevClients[lastFocId];
        petHide = !!(f && f.vis && f.foc && f.fs);
        var a = petArea();
        if (!a)
            return;
        if (petMode === "arrive" && now < petModeT)
            return;   // still waiting off-screen


        // activity bookkeeping (for sleep and dare)
        if (petActT === 0) {
            petActT = now;
            petSCx = cx;
            petSCy = cy;
        }
        // cursor speed in px/s, measured over 100 ms windows (a 16 ms step is too noisy: mouse updates come in bursts)
        var cspd = 0;
        if (now - petSCt >= 100) {
            cspd = petSCt > 0 ? Math.hypot(cx - petSCx, cy - petSCy) / (now - petSCt) * 1000 : 0;
            petSCt = now;
            petSCx = cx;
            petSCy = cy;
        }
        if (Math.abs(cx - petLCx) + Math.abs(cy - petLCy) > 2) {
            petLCx = cx;
            petLCy = cy;
            petMoveT = now;
            petActT = now;
            petDared = false;
        }
        if (scrollT > petActT)
            petActT = scrollT;
        if (clicks !== petLClicks) {
            petLClicks = clicks;
            petActT = now;
        }
        if (petMode === "urgent") {   // circle the urgent tile instead of the focused one
            var uc = prevClients[petUrgId];
            if (uc && uc.vis && uc.w > 120 && uc.h > 120)
                a = { x: uc.x, y: uc.y, w: uc.w, h: uc.h, tile: true };
        }

        if (petPending !== "" && now >= petPendAt)
            petApply(petPending);
        if (petMode === "idle" && petPending === "" && !petBehind) {
            if (now - petActT > 300000)
                petGo("sleep");
            else if (!petDared && now - petMoveT > 10000 && now - petKeyT > 10000 && Math.random() < 0.01)
                petGo("dare");
        }
        if (petMode === "sleep" && petActT > petModeT)
            petGo("flee");   // woken: a quick dart
        if (petMode === "dare") {
            if (petMoveT > petModeT && petMoveT > petKeyT + 700)
                petGo("flee");   // the mouse itself moved (not the cursor jumping because of keys): dash back
            else if (now - Math.max(petModeT, petKeyT) > 20000)
                petGo("idle");
        }
        if (petMode === "urgent" && !fxAlive("urgent", petUrgId))
            petGo("idle");

        // peek: you clicked somewhere far from the pet (not while typing; hint mode clicks come with keys)
        if (clicks !== petPeekClicks) {
            petPeekClicks = clicks;
            if (petMode === "idle" || petMode === "peek" || petMode === "dare")
                petAnswerAt = now + 200 + 200 * Math.random();   // it answers a little later
            if (petMode === "idle" && petPending === "" && now - petKeyT > 3000 && Math.random() < 0.7
                    && Math.hypot(clickX - petPx, clickY - petPy) > root.petAvoid * 1.5)
                petGo("peek");
        }
        if (petAnswerAt > 0 && now >= petAnswerAt) {
            petAnswerAt = 0;
            petRipple(1.0);   // a ring in its own colour answers the click
        }
        if (petMode === "peek" && now - petModeT > 2200)
            petGo("idle");
        // tail: a drag that lasts more than 0.4 s
        if (root.dragging) {
            if (petDragSince === 0)
                petDragSince = now;
        } else {
            petDragSince = 0;
        }
        if (petDragSince > 0 && now - petDragSince > 400 && petMode !== "tail" && petPending !== "tail"
                && (petMode === "idle" || petMode === "type" || petMode === "peek" || petMode === "dare" || petMode === "curious"))
            petGo("tail");
        if (petPending === "tail" && !root.dragging)
            petPending = "";
        if (petMode === "tail" && !root.dragging)
            petGo("idle");
        // lap: once on the hour
        var hd = new Date();
        if (hd.getMinutes() === 0 && hd.getHours() !== petLapHour && petMode === "idle" && petPending === "") {
            petLapHour = hd.getHours();
            petLapMon = "";
            petLapSpd = 0.5;
            petGo("lap");
        }
        var lmm = petLapRect();
        if (petMode === "lap" && lmm && (now - petLapT0) * petLapSpd > petPerim(lmm, 0).P)
            petGo("idle");
        // trick: one every 1-3 min of idle, when the cursor is far away
        if (petNextTrick === 0)
            petNextTrick = now + 60000 + Math.random() * 120000;
        if (petMode === "idle" && petPending === "" && !petBehind && now > petNextTrick) {
            petNextTrick = now + 60000 + Math.random() * 120000;
            if (Math.hypot(cx - petPx, cy - petPy) > root.petAvoid * 2.5)
                petGo("trick");
        }
        if (petMode === "trick" && now - petTrickT0 > petTrickDur + (petTrickGo ? 0 : 2500)) {
            if (petTrickGo && !petTrickRang) {
                petTrickRang = true;
                petRipple(1.5);   // the shape is done
            }
            petGo("idle");
        }
        if (petMode === "perch") {   // sits on the corner until the window stops floating
            var pcl = prevClients[petPerchId];
            if (!pcl || !pcl.vis || !pcl.fl)
                petGo("idle");
        }
        // startle: a very fast cursor flick near the pet makes it shake, then dash away (no waiting: it is a reflex)
        if (cspd > 2500 && now - petStartleT > 6000 && now - petKeyT > 3000 && Math.hypot(cx - petPx, cy - petPy) < 600
                && (petMode === "idle" || petMode === "dare" || petMode === "peek")) {
            petStartleT = now;
            petApply("startle");
        }
        if (petMode === "startle" && now - petModeT > 800)
            petApply("flee");
        if (petMode === "type") {
            if (now - petKeyT < 700) {   // the cursor moves with the keys (hint mode, SUPER+d): that is not the mouse
                petCurX = cx;
                petCurY = cy;
            } else if (Math.abs(cx - petCurX) + Math.abs(cy - petCurY) > 20)
                petGo("flee");   // the mouse itself moved: go somewhere else
            else if (now - petKeyT > 2500)
                petGo("idle");
        }
        if (petMode === "flee" && now - petModeT > 700)
            petGo("idle");
        if (petMode === "curious" && now - petModeT > 9000)
            petGo("idle");   // gave up (never got there)
        // `annoying` switch: now and then ask hintd for the clickable things near the pet, and click one
        if (petMode === "idle" && petPending === "" && !petBehind && !petPokeQ.running && now > petPokeNext && fxOn("annoying")) {
            petPokeNext = now + pokeMin * 1000 + Math.random() * (pokeMax - pokeMin) * 1000;
            if (now - petKeyT > 8000 && Math.hypot(petPx - cx, petPy - cy) > root.petAvoid * 2)
                petPokeAsk();
        }

        var tx = petTx, ty = petTy;
        // Motion is a critically damped spring (w = stiffness in rad/s): it always starts and stops smoothly.
        var w = 3;
        var avoid = true;
        var fadeT = 1;
        var m;

        // the cursor bothering it for too long (staying near it) sends it to hide under the focused tile
        if (petMode !== "hide" && petMode !== "arrive" && petMode !== "type" && petMode !== "dare" && petMode !== "sleep" && petMode !== "peek" && petMode !== "tail" && petMode !== "lap" && petMode !== "startle" && petPending !== "hide") {
            if (Math.hypot(petPx - cx, petPy - cy) < root.petAvoid * 1.3)
                petAnnoy += dt;
            else
                petAnnoy = Math.max(0, petAnnoy - dt * 0.4);
            if (petAnnoy > 7000 && a.tile) {
                petAnnoy = 0;
                petGo("hide");
            }
        }
        var e1 = 0.5 + 0.5 * en;

        if (petMode === "type") {
            // typing: stop where it is and stay completely still (only the small hop on each key remains)
            tx = petFreezeX;
            ty = petFreezeY;
            w = 9;
            avoid = false;
        } else if (petMode === "hide") {
            // go to a gap between tiles, switch to the layer under the windows right there, slip under a tile,
            // wait, then come back out through the same gap and switch back
            w = 3.4;
            avoid = false;
            if (petHidePhase === "gap") {   // dash straight to the gap (the movement itself is below)
                tx = petGapX;
                ty = petGapY;
                if ((petGapX - petPx) * petRunDX + (petGapY - petPy) * petRunDY <= 0) {   // reached the gap: switch layer, keep going
                    petBehind = true;
                    petHidePhase = "slide";
                    petSlide = 70;
                }
            } else if (petHidePhase === "slide") {   // carry on under the tile at the same speed and direction
                petSlide -= 650 * dt / 1000;
                if (petSlide <= 0) {
                    petHidePhase = "under";
                    petHideUntil = now + 8000 + Math.random() * 8000;
                }
            } else if (petHidePhase === "under") {
                tx = petUnderX + 30 * Math.sin(now * 0.0007 + petPh1);
                ty = petUnderY + 20 * Math.cos(now * 0.0009 + petPh2);
                if (now > petHideUntil && (petAfter !== "" || Math.hypot(cx - petPx, cy - petPy) > root.petAvoid * 1.6))
                    petHidePhase = "out";
            } else {
                tx = petGapX;
                ty = petGapY;
                if (Math.hypot(petPx - tx, petPy - ty) < 14) {
                    var nextMode = petAfter !== "" ? petAfter : "idle";
                    petAfter = "";
                    petAnnoy = 0;
                    petBehind = false;
                    petApply(nextMode);
                }
            }
        } else if (petMode === "flee") {
            w = 6;
        } else if (petMode === "curious") {
            m = prevMons[mon];
            var bx0 = m ? m.x : (Quickshell.screens.length > 0 ? Quickshell.screens[0].x : 0);
            var by0 = m ? m.y : (Quickshell.screens.length > 0 ? Quickshell.screens[0].y : 0);
            tx = bx0 + 190 + 90 * Math.sin(now * 0.0013 + petPh1) + 30 * Math.sin(now * 0.0031 + petPh2);
            ty = by0 + 80 + 28 * Math.cos(now * 0.0011 + petPh2);
            w = 7;
            // first fly all the way there; only then look around for a few seconds, then go back
            if (petCurPhase === "go") {
                if (Math.hypot(petPx - tx, petPy - ty) < 80) {
                    petCurPhase = "look";
                    petLookT = now;
                }
            } else if (now - petLookT > 2500) {
                petGo("idle");
            }
        } else if (petMode === "sleep") {
            // park in a corner of the tile and stay still
            var scx = (petSlpC % 2 === 0) ? a.x + 34 : a.x + a.w - 34;
            var scy = (petSlpC < 2) ? a.y + 34 : a.y + a.h - 34;
            tx = scx;
            ty = scy;
            if (!petSleepRang && Math.hypot(petPx - tx, petPy - ty) < 10) {
                petSleepRang = true;
                petRipple(0.5);   // parked
            }
            w = 3;
            avoid = false;
        } else if (petMode === "urgent") {
            // circle the urgent tile along its outline
            petS += 120 * (0.5 + 0.5 * en) * dt / 1000;
            var upp = petPerim(a, petS);
            tx = upp.x;
            ty = upp.y;
            w = 4.5;
        } else if (petMode === "dare") {
            // creep toward the still cursor, to just outside its zone
            var ddx = petPx - cx, ddy = petPy - cy;
            var ddd = Math.max(1, Math.hypot(ddx, ddy));
            var dr0 = root.petAvoid * 1.2;
            tx = cx + ddx / ddd * dr0;
            ty = cy + ddy / ddd * dr0;
            w = 1.2;
            avoid = false;
            if (petDareT === 0 && Math.hypot(petPx - tx, petPy - ty) < 20 && Math.hypot(petVx, petVy) < 15)
                petDareT = now;   // settled
            if (petDareT > 0) {
                // 1 s after settling: one ring; 5 s after: two more
                var dd = now - petDareT;
                if (petDareStage === 0 && dd >= 1000) { petDareStage = 1; petRipple(1.0); }
                else if (petDareStage === 1 && dd >= 5000) { petDareStage = 2; petRipple(1.0); }
                else if (petDareStage === 2 && dd >= 5300) { petDareStage = 3; petRipple(1.0); }
            }
        } else if (petMode === "peek") {
            // curious about the click: go to just outside the avoid zone, on the pet's side of the click spot
            var kdx = petPx - clickX, kdy = petPy - clickY;
            var kdd = Math.max(1, Math.hypot(kdx, kdy));
            tx = clickX + kdx / kdd * root.petAvoid * 1.2;
            ty = clickY + kdy / kdd * root.petAvoid * 1.2;
            w = 4;
            avoid = false;
        } else if (petMode === "tail") {
            // while you drag: trail 150 px behind the cursor, like a kite on a string
            var gdx = petPx - cx, gdy = petPy - cy;
            var gdd = Math.max(1, Math.hypot(gdx, gdy));
            tx = cx + gdx / gdd * 150;
            ty = cy + gdy / gdd * 150;
            w = 5;
            avoid = false;
        } else if (petMode === "lap") {
            // one fast lap around the edges of the screen (500 px/s along the outline)
            var lm = petLapRect();
            if (lm) {
                var lp = petPerim(lm, (now - petLapT0) * petLapSpd);
                tx = lp.x;
                ty = lp.y;
            }
            w = 6;
            avoid = false;
        } else if (petMode === "trick") {
            var tt = petTrickGo ? Math.min(now - petTrickT0, petTrickDur) / 1000 : 0;   // 0 = the start of the shape: first fly there
            if (petTrickKind === "loop") {
                var ph = petTrickH - Math.PI / 2 + tt / 1.6 * 2 * Math.PI;
                tx = petTrickCX + 90 * Math.cos(ph);
                ty = petTrickCY + 90 * Math.sin(ph);
            } else if (petTrickKind === "eight") {
                var te = tt / 2.6 * 2 * Math.PI;
                var eu = 170 * Math.sin(te), ev = 90 * Math.sin(2 * te);
                tx = petTrickCX + eu * Math.cos(petTrickH) - ev * Math.sin(petTrickH);
                ty = petTrickCY + eu * Math.sin(petTrickH) + ev * Math.cos(petTrickH);
            } else if (petTrickKind === "slalom") {   // forward along the run, swinging 60 px to both sides, 2.5 swings
                var sf = Math.min(1, tt * 1000 / petTrickDur);
                var sp = sf < 0.5 ? sf * 2 : (1 - sf) * 2;   // there and back along the same weave
                var sam = Math.min(45, Math.pow(petTrickLen / 2, 2) / (4 * Math.PI * Math.PI * 75));   // swing width the pet can really follow
                var sl = sp * petTrickLen, sv = sam * Math.sin(sp * 2 * 2 * Math.PI);
                tx = petTrickCX + sl * Math.cos(petTrickH) - sv * Math.sin(petTrickH);
                ty = petTrickCY + sl * Math.sin(petTrickH) + sv * Math.cos(petTrickH);
            } else if (petTrickKind === "clover") {   // four circles of 75 px that all pass through the middle (no tighter turn than the pet can make)
                var cp = Math.min(0.9999, (tt * 1000 / petTrickCycle) % 1) * 4;   // the four petals, repeated
                var ck = Math.floor(cp), cf = cp - ck;
                var cal = ck * Math.PI / 2;
                var cph = cal + Math.PI + 2 * Math.PI * cf;
                var cu = 75 * Math.cos(cal) + 75 * Math.cos(cph), cv = 75 * Math.sin(cal) + 75 * Math.sin(cph);
                var crot = petTrickH + Math.PI / 2;
                tx = petTrickCX + cu * Math.cos(crot) - cv * Math.sin(crot);
                ty = petTrickCY + cu * Math.sin(crot) + cv * Math.cos(crot);
            } else if (petTrickKind === "pendulum") {   // a swing that dies down
                var pa = petTrickH * Math.cos(2 * Math.PI * tt / 1.3) * Math.exp(-tt / 3.2);
                tx = petTrickCX + 150 * Math.sin(pa);
                ty = petTrickCY + 150 * Math.cos(pa);
            } else if (petTrickKind === "tile") {
                var tp = petPerim(a, petTrickS0 + tt * 450);
                tx = tp.x;
                ty = tp.y;
            } else if (petTrickKind === "dvd" && petDvd) {
                var dp = dvdAt(petDvd, tt);
                tx = dp.x;
                ty = dp.y;
            } else {   // zoom: straight across the tile to the opposite side
                tx = Math.max(a.x + 20, Math.min(a.x + a.w - 20, 2 * (a.x + a.w / 2) - petTrickCX));
                ty = Math.max(a.y + 20, Math.min(a.y + a.h - 20, 2 * (a.y + a.h / 2) - petTrickCY));
            }
            if (petTrickM) {   // never aim off the screen (a slalom or a tile lap can reach the edge)
                tx = Math.max(petTrickM.x + 16, Math.min(petTrickM.x + petTrickM.w - 16, tx));
                ty = Math.max(petTrickM.y + 16, Math.min(petTrickM.y + petTrickM.h - 16, ty));
            }
            if (!petTrickGo && (Math.hypot(petPx - tx, petPy - ty) < 30 || now - petTrickT0 > 1500)) {
                petTrickGo = true;   // at the start: now draw it
                petTrickT0 = now;
                petRipple(1.0);
                petTrickOX = petPx - tx;
                petTrickOY = petPy - ty;
            }
            w = 7;
            avoid = false;
        } else if (petMode === "perch") {
            var pch = prevClients[petPerchId];
            if (pch) {
                tx = pch.x + 20;
                ty = pch.y + 20;
            }
            if (!petPerchRang && Math.hypot(petPx - tx, petPy - ty) < 10) {
                petPerchRang = true;
                petRipple(0.5);   // landed
            }
            w = 5;
            avoid = false;
        } else if (petMode === "startle") {
            tx = petPx;   // frozen, shaking
            ty = petPy;
            w = 10;
            avoid = false;
        } else if (petMode === "poke") {
            // fly to a clickable thing found by hintd, hover a moment, click it, then go back to idle
            var pokeSit = petPokePhase !== "go" || Math.hypot(petPx - petPokeX, petPy - petPokeY) < 60;
            tx = petPokeX + (pokeSit ? 0 : 5 * Math.sin(now * 0.004 + petPh1));   // on the button: no wobble at all
            ty = petPokeY + (pokeSit ? 0 : 5 * Math.cos(now * 0.005 + petPh2));
            w = pokeSit ? 9 : 6;
            var pokeBad = now - petModeT > 7000 || lastFocId !== petPokeFoc || now - petKeyT < 1500
                || Math.hypot(cx - petPokeX, cy - petPokeY) < root.petAvoid * 0.8;
            if (pokeBad) {
                petGo("idle");
            } else if (petPokePhase === "go") {
                // arrived = on the spot AND stopped; only then does the 1 s start
                if (Math.hypot(petPx - petPokeX, petPy - petPokeY) < 2 && Math.hypot(petVx, petVy) < 6) {
                    petPokePhase = "hold";
                    petRipple(0.4);
                    petPokeAt = now + 1000;   // sits completely still for 1 s, then clicks
                }
            } else if (petPokePhase === "hold") {
                if (now >= petPokeAt) {
                    petPokeClick.command = ["bash", "-c", "printf 'click " + petPokeMon + " " + petPokeLx + " " + petPokeLy
                        + " l\\n' | timeout 3 socat -t2 - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock"];
                    petPokeClick.running = true;
                    petRipple(0.7);
                    petPokePhase = "after";
                    petPokeAt = now + 800;
                }
            } else if (now >= petPokeAt) {
                petGo("idle");
            }
        } else {   // idle and arrive: a slow, wandering drift along the outline of the window
            petSv += (Math.random() - 0.5) * dt * 0.25;
            var vmax = 70 * e1;
            petSv = Math.max(-vmax, Math.min(vmax, petSv));
            if (Math.abs(petSv) < 15 * e1)
                petSv = (petSv < 0 ? -1 : 1) * 15 * e1;
            petS += petSv * dt / 1000;
            var pp = petPerim(a, petS);
            tx = pp.x + 16 * Math.sin(now * 0.0007 + petPh1) + 8 * Math.sin(now * 0.0019 + petPh2);
            ty = pp.y + 16 * Math.cos(now * 0.0009 + petPh2) + 8 * Math.sin(now * 0.0017 + petPh1);
            w = 3.2;
            if (petMode === "arrive") {
                w = 2.6;
                ty += Math.sin(now * 0.006) * 40;   // a swoop on the way in
                if (Math.hypot(petPx - tx, petPy - ty) < 60 || now - petModeT > 2600) {
                    petMode = "idle";
                    petModeT = now;
                }
            }
        }

        if (avoid) {   // the cursor came near where the pet floats, or across its path: pick another spot, further away
            if ((petMode === "idle" || petMode === "arrive") && now - petRelocT > 400
                    && (Math.hypot(tx - cx, ty - cy) < root.petAvoid || Math.hypot(petPx - cx, petPy - cy) < root.petAvoid
                        || petSegDist(petPx, petPy, tx, ty, cx, cy) < root.petAvoid * 0.8)) {
                petRelocT = now;
                petRelocate(a);
                var pq = petPerim(a, petS);
                tx = pq.x;
                ty = pq.y;
            }
            if (Math.hypot(petPx - cx, petPy - cy) < root.petAvoid)
                w *= 1.7;
        }

        petFade += (fadeT - petFade) * Math.min(1, dt / 350);
        petDim += ((petMode === "sleep" ? 0.35 : 1) - petDim) * Math.min(1, dt / 900);
        // the trail grows while a trick is being drawn, so the path stays visible as a shape, then draws back in
        var lifeT = 450;
        if (petMode === "trick") {
            if (petTrickGo && now - petTrickT0 < petTrickDur) {
                var lifeMap = { loop: 2600, eight: 4200, zoom: 1400, slalom: 3200, clover: 4200, pendulum: 3600, tile: 1100, dvd: 700 };
                lifeT = lifeMap[petTrickKind] || 1400;
            }
        }
        petLife += (lifeT - petLife) * Math.min(1, dt / (lifeT > petLife ? 300 : 900));
        petW += (w - petW) * Math.min(1, dt / 260);   // ease the stiffness itself, so a change of mode never jerks
        w = petW;
        petTx = tx;
        petTy = ty;
        var ds = dt / 1000;
        var run = petMode === "hide" && (petHidePhase === "gap" || petHidePhase === "slide");
        if (run) {   // a straight dash at one constant speed: no easing, no curve
            var rs = 650;   // px/s
            petPx += petRunDX * rs * ds;
            petPy += petRunDY * rs * ds;
            petVx = petRunDX * rs;
            petVy = petRunDY * rs;
            petHead = Math.atan2(petRunDY, petRunDX);
        } else if (petMode === "trick" && petTrickGo && now - petTrickT0 < petTrickDur) {
            // drawing a shape: the pet sits exactly on the path (no steering, no turning limit), so the shape comes out right.
            // The few px left from the lead-in fade away in 250 ms, so there is no jump.
            var kdec = Math.exp(-(now - petTrickT0) / 250);
            var knx = tx + petTrickOX * kdec, kny = ty + petTrickOY * kdec;
            petVx = (knx - petPx) / ds;
            petVy = (kny - petPy) / ds;
            petPx = knx;
            petPy = kny;
            if (Math.hypot(petVx, petVy) > 20)
                petHead = Math.atan2(petVy, petVx);
        } else if ((petMode === "poke" && Math.hypot(petPx - petPokeX, petPy - petPokeY) < 40)
                   || (petMode === "perch" && Math.hypot(petPx - tx, petPy - ty) < 40)
                   || (petMode === "sleep" && Math.hypot(petPx - tx, petPy - ty) < 40)) {
            // the last 40 px onto the button: a soft landing that really stops (a vehicle with a turning radius would circle it)
            var sw = 8;
            petVx += (sw * sw * (tx - petPx) - 2 * sw * petVx) * ds;
            petVy += (sw * sw * (ty - petPy) - 2 * sw * petVy) * ds;
            petPx += petVx * ds;
            petPy += petVy * ds;
            if (Math.hypot(petVx, petVy) > 20)
                petHead = Math.atan2(petVy, petVx);
        } else {
        // Steering, like a vehicle: it turns toward the target no faster than a minimum turning radius allows
        // (so every path is a smooth curve), and speeds up and slows down gently (its speed follows the distance).
        var sp0 = Math.hypot(petVx, petVy);
        var tdx = tx - petPx, tdy = ty - petPy;
        var tdist = Math.hypot(tdx, tdy);
        var vmaxM = (petMode === "flee" ? 520 : (petMode === "arrive" ? 420 : (petMode === "type" || petMode === "curious" ? 460 : 340))) * (0.5 + 0.5 * en);
        if (petMode === "dare")
            vmaxM = Math.min(vmaxM, 110);   // creeps
        if (petMode === "lap")
            vmaxM = Math.max(vmaxM, 650);
        if (petMode === "trick")
            vmaxM = petTrickKind === "zoom" ? 700 : (petTrickKind === "tile" ? 560 : (petTrickKind === "dvd" ? 600 : 520));
        if (petMode === "tail")
            vmaxM = Math.max(vmaxM, 520);
        var vt = Math.min(vmaxM, tdist * w);   // wanted speed
        // Chased: when the cursor is near, the wanted heading bends away from it (more the closer it is) and the pet
        // speeds up. It still turns only as fast as the minimum radius allows.
        var wantA = Math.atan2(tdy, tdx);
        var chased = false;
        if (avoid) {
            var rx = petPx - cx, ry = petPy - cy;
            var rd = Math.hypot(rx, ry);
            var zone = root.petAvoid * 1.5;
            if (rd < zone) {
                var wt = Math.min(1, (zone - rd) / (zone * 0.6));   // 0 at the edge of the zone, 1 when close
                var ux = rx / Math.max(rd, 1), uy = ry / Math.max(rd, 1);
                var gx = Math.cos(wantA) * (1 - wt) + ux * wt, gy = Math.sin(wantA) * (1 - wt) + uy * wt;
                if (Math.hypot(gx, gy) < 0.05) { gx = -uy; gy = ux; }   // target straight behind the cursor: slip sideways
                wantA = Math.atan2(gy, gx);
                vt = Math.max(vt, 520 * (0.5 + 0.5 * en) * wt);
                chased = true;
            }
        }
        // Slow down for a sharp turn instead of looping wide: at speed v the turning circle is v wide (below 70 px/s),
        // so when the target is off to the side or behind, cap the speed to what a circle that fits needs.
        if (!chased && tdist > 8) {
            var dab = wantA - petHead;
            dab = Math.abs(Math.atan2(Math.sin(dab), Math.cos(dab)));
            if (dab > 0.35) {
                var rreq = tdist / (2 * Math.max(dab < Math.PI / 2 ? Math.sin(dab) : 1, 0.05));   // radius of the circle that reaches the target
                if (rreq < root.petTurnR)
                    vt = Math.min(vt, Math.max(18, rreq * 70 / root.petTurnR));
            }
        }
        sp0 += Math.max(-700 * ds, Math.min(700 * ds, vt - sp0));   // at most 700 px/s^2
        var da = wantA - petHead;
        da = Math.atan2(Math.sin(da), Math.cos(da));   // -pi..pi
        var turn = Math.max(sp0, 70) / root.petTurnR * ds;   // radians this frame: speed / minimum radius
        petHead += Math.max(-turn, Math.min(turn, da));
        petVx = Math.cos(petHead) * sp0;
        petVy = Math.sin(petHead) * sp0;

        // speed limit (a little more for a moment after a bounce)
        var spd = Math.hypot(petVx, petVy);
        var cap = ((petMode === "flee" || chased) ? 520 : (petMode === "arrive" ? 420 : (petMode === "type" || petMode === "curious" ? 460 : 340))) * (0.5 + 0.5 * en);
        if (petMode === "dare")
            cap = Math.min(cap, 110);
        if (petMode === "lap")
            cap = Math.max(cap, 650);
        if (petMode === "trick")
            cap = petTrickKind === "zoom" ? 700 : (petTrickKind === "tile" ? 560 : (petTrickKind === "dvd" ? 600 : 520));
        if (petMode === "tail")
            cap = Math.max(cap, 520);
        cap *= 1 + 0.6 * Math.max(0, 1 - (now - petBounceT) / 500);
        if (spd > cap) {
            petVx *= cap / spd;
            petVy *= cap / spd;
        }
        var ox = petPx, oy = petPy;
        petPx += petVx * ds;
        petPy += petVy * ds;

        // (no pushing or snapping away from the cursor: avoiding is done by steering above, so a fast cursor
        // can catch the pet, but the pet never jumps or turns sharper than its minimum radius)

        // bounce off the screen edge, with 1.5x the speed it arrived with
        if (petOnScreen(ox, oy) && !petOnScreen(petPx, petPy)) {
            if (!petOnScreen(petPx, oy)) {
                petVx = (petPx > ox ? -1 : 1) * Math.max(Math.abs(petVx) * 1.5, 150);
                petPx = ox;
                petBounceT = now;
            }
            if (!petOnScreen(petPx, petPy)) {
                petVy = (petPy > oy ? -1 : 1) * Math.max(Math.abs(petVy) * 1.5, 150);
                petPy = oy;
                petBounceT = now;
            }
        }
        if (Math.hypot(petVx, petVy) > 20)   // a push or a bounce turned it: keep the heading in step
            petHead = Math.atan2(petVy, petVx);
        }

        // the eye: a tiny quick shift of the position at random times (see petNextJit)
        if (now >= petNextJit) {
            var ja = 7.2 * (0.5 + en);
            petJtx = (Math.random() - 0.5) * 2 * ja;
            petJty = (Math.random() - 0.5) * 2 * ja;
            petNextJit = now + 180 + Math.random() * Math.random() * 2000;   // 0.18-2.2 s, mostly short, sometimes a long pause
        }
        var dvdNow = petMode === "trick" && petTrickKind === "dvd";   // the DVD trick: hard, exact motion, no easing
        if (run || dvdNow) {   // no eye shifts during the dash or the dvd trick
            petJtx = 0;
            petJty = 0;
        }
        var jk = Math.min(1, dt / (140 + 160 * (1 - en)));   // the shift is eased: about 0.15-0.3 s, never instant
        if (dvdNow) {
            petJx = 0;
            petJy = 0;
        }
        petJx += (petJtx - petJx) * jk;
        petJy += (petJty - petJy) * jk;
        if (petMode === "sleep" || (petMode === "perch" && Math.hypot(petPx - tx, petPy - ty) < 40) || (petMode === "poke" && (petPokePhase !== "go" || Math.hypot(petPx - petPokeX, petPy - petPokeY) < 60))) {
            petJx = 0;   // sitting on the button: not even the eye jitter
            petJy = 0;
        }
        if (petMode === "startle") {   // shaking: a fast tremble of about 9 px, every frame
            petJx = (Math.random() - 0.5) * 18;
            petJy = (Math.random() - 0.5) * 18;
        }
        var hopY = (petMode === "type" && now - petHopT < 200) ? -12 * Math.sin(Math.PI * (now - petHopT) / 200) : 0;   // a hop per key
        var nx = petPx + petJx;
        var ny = petPy + petJy + hopY;
        petV = petV * (dvdNow ? 0 : 0.6) + (Math.hypot(nx - petX, ny - petY) / dt) * (dvdNow ? 1 : 0.4);
        petX = nx;
        petY = ny;
        petSeq++;
    }

    // Runs only on AC with the `pet` switch on. 60 fps by day (the canvas repaint is the cost); 30 fps at night (the pet is drowsy).
    Timer {
        id: petTick
        interval: 16
        repeat: true
        running: root.petOn
        onTriggered: {
            root.petStep();
            root.wildStep(Date.now());
            interval = (root.petMode === "sleep" && root.petV < 0.01 && !root.wildBusy()) ? 100 : (root.petEnergy() < 0.4 ? 33 : 16);
        }
    }

    // ---- Wild swarms: swarmFlocks - 1 more swarms (the pet is the first) that live simple lives around the pet.
    // They only READ the pet's state (they react to it, it does not react to them), except that a merge can burst the
    // pet's lights and tint them. Everything here is in global compositor coordinates; WildView draws them.
    // What they do, in order of priority: panic (cursor, or a wave from a scared swarm) > sleep pile (the pet sleeps)
    // > join a trick (the pet draws a shape) > merge > tag > wander. Switches: `swarm` and `flocks` in effects.conf. ----
    property int swarmFlocks: 3          // swarms in total, the pet included (restart to apply)
    property var wild: []                // the wild swarms, see wildMake()
    property int wildSeq: 0              // bumps every step; the windows listen
    property double wildT: 0
    // colours: the pet is hue turn 0.5, the others are spread evenly around the wheel from there
    property var wildLuts: {
        var out = [];
        for (var i = 0; i < Math.max(0, swarmFlocks - 1); i++)
            out.push(hueShift(glowLut, (0.5 + (i + 1) / swarmFlocks) % 1));
        return out;
    }
    property var petHist: []             // the pet's recent positions {x, y, t}: the swarms that join a trick follow it
    property string wildPrevMode: ""     // the pet's mode one step ago (to catch the moment it panics)
    property bool wildFast: false        // the same end-of-trick rule the pet's own lights use (see stepSwarm)
    property bool wildCut: false
    property bool wildDrawing: false     // the pet is drawing a trick shape
    property double petBurstAt: 0        // ms: the pet's lights must burst (end of a merge); every view bursts once per value
    property var wildTag: null           // a game of tag: { chaser, runner, until, swaps, swapT } (indexes of wild swarms)
    property var wildMerge: null         // a merge: { a, b, phase, t0 }: a = wild swarm, b = wild swarm or -1 for the pet
    property double wildNextTag: 0
    property double wildNextMerge: 0
    property real petMixTarget: 0

    function wildMake(i, x, y) {
        var fl = [];
        for (var j = 0; j < swarmCount; j++)
            fl.push({ x: x, y: y, vx: 0, vy: 0, ph: Math.random() * 6.28,
                      w: j === 0 ? 1.3 : 1.2 + Math.random() * 1.4, r: j === 0 ? 0.5 : 0.6 + Math.random() * 0.6 });
        return { i: i, x: x, y: y, vx: 0, vy: 0, tx: x, ty: y, next: 0, mode: "wander", fade: 0, dim: 1,
                 flies: fl, hist: [], shape: 0, scat: 0, boom: 0, moodKind: "red", moodA: 0, mixTint: "", mixA: 0, mixTarget: 0,
                 pending: null, panicUntil: 0, scareCool: 0, fx: 0, fy: 0 };
    }
    function wildInit(n, now) {
        var out = [];
        for (var i = 0; i < n; i++) {
            var ang = Math.random() * Math.PI * 2, r = 120 + Math.random() * 100;
            var x = petPx + Math.cos(ang) * r, y = petPy + Math.sin(ang) * r;
            if (!petOnScreen(x, y)) {
                x = petPx;
                y = petPy;
            }
            out.push(wildMake(i, x, y));
        }
        wild = out;
        wildT = now;
        wildTag = null;
        wildMerge = null;
        wildNextTag = now + 25000 + Math.random() * 15000;
        wildNextMerge = now + 15000 + Math.random() * 10000;
    }
    function wildBusy() {   // any wild swarm still moving: the tick must not drop to its sleepy rate
        for (var i = 0; i < wild.length; i++)
            if (Math.hypot(wild[i].vx, wild[i].vy) > 8)
                return true;
        return false;
    }
    function wildStep(now) {
        var n = (petOn && fxOn("swarm") && fxOn("flocks") && petMode !== "arrive") ? Math.max(0, swarmFlocks - 1) : 0;
        if (n === 0) {
            if (wild.length > 0) {
                wild = [];
                wildTag = null;
                wildMerge = null;
                petMixTarget = 0;
                petMixA = 0;
                petHist = [];
                wildPrevMode = "";
                wildFast = false;
                wildCut = false;
                wildDrawing = false;
                wildSeq++;
            }
            return;
        }
        if (wild.length !== n)
            wildInit(n, now);
        var dt = Math.min(0.05, Math.max(0.001, (now - wildT) / 1000));
        wildT = now;
        petHist.push({ x: petPx, y: petPy, t: now });
        while (petHist.length > 0 && now - petHist[0].t > 4000)
            petHist.shift();
        // is the pet drawing a trick shape? (the same rule the pet's own lights use)
        var inTrick = petMode === "trick" && petTrickGo;
        if (!inTrick) {
            wildFast = false;
            wildCut = false;
        } else if (!wildCut) {
            if (petTrickKind === "pendulum") {
                if (now - petTrickT0 > petTrickDur * 0.75)
                    wildCut = true;
            } else if (petV > 0.2) {
                wildFast = true;
            } else if (wildFast && petV < 0.12 && now - petTrickT0 > 600) {
                wildCut = true;
            }
        }
        wildDrawing = inTrick && !wildCut;
        // the pet panics: a wave goes out
        if ((petMode === "flee" || petMode === "startle") && wildPrevMode !== "flee" && wildPrevMode !== "startle")
            wildWave(petPx, petPy, now, -1);
        wildPrevMode = petMode;
        wildGames(now);
        for (var i = 0; i < wild.length; i++) {
            wildBrain(wild[i], dt, now);
            wildLights(wild[i], dt, now);
        }
        petMixA += (petMixTarget - petMixA) * Math.min(1, dt * 6);
        wildSeq++;
    }

    // Where a swarm wanders to: somewhere around the pet (the leash), on a screen.
    function wildPickTarget(sw, now) {
        for (var tries = 0; tries < 8; tries++) {
            var ang = Math.random() * Math.PI * 2, r = 100 + Math.random() * 250;
            var px = petPx + Math.cos(ang) * r, py = petPy + Math.sin(ang) * r;
            if (petOnScreen(px, py)) {
                sw.tx = px;
                sw.ty = py;
                break;
            }
        }
        sw.next = now + 1500 + Math.random() * 3000;
    }

    // Scares a swarm away from (fx, fy) for 1.2 s. A scare ends any game it is in.
    function wildScare(sw, fx, fy, now) {
        sw.mode = "panic";
        sw.fx = fx;
        sw.fy = fy;
        sw.panicUntil = now + 1200;
        sw.scareCool = now + 4000;
        if (wildTag && (wildTag.chaser === sw.i || wildTag.runner === sw.i)) {
            wildTag = null;
            wildNextTag = now + 30000 + Math.random() * 30000;
        }
        if (wildMerge && (wildMerge.a === sw.i || wildMerge.b === sw.i))
            wildMergeEnd(false, now);
    }
    // A wave of fright from (x, y): every other swarm within 450 px is scared a moment later (the further, the later).
    // A swarm scared by a wave does not start a new wave, so it dies out.
    function wildWave(x, y, now, srcIdx) {
        for (var i = 0; i < wild.length; i++) {
            var sw = wild[i];
            if (sw.i === srcIdx || sw.mode === "panic" || now < sw.scareCool)
                continue;
            var d = Math.hypot(sw.x - x, sw.y - y);
            if (d < 450)
                sw.pending = { fx: x, fy: y, at: now + d / 1.1 };   // a wave front of 1100 px/s
        }
    }
    function wildPanicNow() {   // IPC preview: a wave from the pet
        wildWave(petPx, petPy, Date.now(), -1);
    }

    // The lights of one wild swarm burst outward and take new random orbits (see stepSwarm in Layer).
    function wildBurst(sw) {
        var fl = sw.flies;
        var mx = 0, my = 0;
        for (var c0 = 0; c0 < fl.length; c0++) {
            mx += fl[c0].x / fl.length;
            my += fl[c0].y / fl.length;
        }
        for (var b = 0; b < fl.length; b++) {
            var bf = fl[b];
            var bx = bf.x - mx, by = bf.y - my, bd = Math.hypot(bx, by);
            if (bd < 6) {
                var ba = Math.random() * Math.PI * 2;
                bx = Math.cos(ba);
                by = Math.sin(ba);
                bd = 1;
            }
            var bs = 320 + Math.random() * 220;
            bf.vx += bx / bd * bs;
            bf.vy += by / bd * bs;
            bf.ph = Math.random() * 6.28;
            bf.w = b === 0 ? 1.3 : 1.2 + Math.random() * 1.4;
        }
        sw.shape = 0;
        sw.boom = 1;
        sw.scat = Math.max(sw.scat, 0.55);
    }

    // Tag and merge: starting, running and ending them. They start by themselves now and then, when everything is calm.
    function wildStartTag(now) {
        if (wild.length < 2)
            return;
        var a = Math.floor(Math.random() * wild.length);
        var b = (a + 1 + Math.floor(Math.random() * (wild.length - 1))) % wild.length;
        wildMerge = null;
        wildTag = { chaser: a, runner: b, until: now + 14000, swaps: 0, swapT: now };
    }
    function wildStartMerge(now) {
        if (wild.length < 1)
            return;
        var a = Math.floor(Math.random() * wild.length);
        var b = -1;
        if (wild.length > 1 && Math.random() < 0.5)
            b = (a + 1 + Math.floor(Math.random() * (wild.length - 1))) % wild.length;
        wildTag = null;
        wildMerge = { a: a, b: b, phase: "approach", t0: now };
    }
    function wildMergeEnd(burst, now) {
        var m = wildMerge;
        wildMerge = null;
        wildNextMerge = now + 25000 + Math.random() * 25000;
        if (!m || !burst)
            return;
        if (wild[m.a])
            wildBurst(wild[m.a]);
        if (m.b >= 0 && wild[m.b])
            wildBurst(wild[m.b]);
        else
            petBurstAt = now;   // the pet's own lights burst too
    }
    function wildGames(now) {
        var A, B, d;
        if (wildMerge) {
            A = wild[wildMerge.a];
            B = wildMerge.b >= 0 ? wild[wildMerge.b] : null;
            var bx = B ? B.x : petPx, by = B ? B.y : petPy;
            d = Math.hypot(A.x - bx, A.y - by);
            var busy = petMode === "sleep" || wildDrawing || A.mode === "panic" || A.mode === "sleep" || A.mode === "join"
                       || (B && (B.mode === "panic" || B.mode === "sleep" || B.mode === "join")) || (!B && (petMode === "flee" || petMode === "startle"));
            if (busy) {
                wildMergeEnd(false, now);
            } else if (wildMerge.phase === "approach") {
                if (d < 55) {
                    wildMerge.phase = "hold";
                    wildMerge.t0 = now;
                } else if (now - wildMerge.t0 > 8000) {
                    wildMergeEnd(false, now);
                }
            } else if (now - wildMerge.t0 > 1500) {
                wildMergeEnd(true, now);
            }
        }
        if (wildTag) {
            var C = wild[wildTag.chaser], R = wild[wildTag.runner];
            if (petMode === "sleep" || wildDrawing || C.mode === "sleep" || R.mode === "sleep" || C.mode === "join" || R.mode === "join") {
                wildTag = null;
                wildNextTag = now + 30000 + Math.random() * 30000;
            } else {
                d = Math.hypot(C.x - R.x, C.y - R.y);
                if (d < 45 && now - wildTag.swapT > 1200) {   // caught: swap roles
                    var tmp = wildTag.chaser;
                    wildTag.chaser = wildTag.runner;
                    wildTag.runner = tmp;
                    wildTag.swaps++;
                    wildTag.swapT = now;
                }
                if (wildTag.swaps >= 4 || now > wildTag.until) {
                    wildTag = null;
                    wildNextTag = now + 30000 + Math.random() * 30000;
                }
            }
        }
        // start something new when everything is calm
        var calm = petMode !== "sleep" && petMode !== "trick" && petMode !== "arrive" && !wildDrawing;
        for (var i = 0; i < wild.length && calm; i++)
            if (wild[i].mode !== "wander")
                calm = false;
        if (calm && !wildTag && !wildMerge) {
            if (now > wildNextTag && wild.length >= 2)
                wildStartTag(now);
            else if (now > wildNextMerge && petMode === "idle")
                wildStartMerge(now);
        }
        // merge colours: the two swarms blend toward each other (more the closer they are, fully while they hold)
        for (var k = 0; k < wild.length; k++)
            wild[k].mixTarget = 0;
        petMixTarget = 0;
        if (wildMerge) {
            A = wild[wildMerge.a];
            B = wildMerge.b >= 0 ? wild[wildMerge.b] : null;
            var px = B ? B.x : petPx, py = B ? B.y : petPy;
            var dd = Math.hypot(A.x - px, A.y - py);
            var tg = wildMerge.phase === "hold" ? 1 : Math.max(0, Math.min(0.5, 1 - (dd - 55) / 200));
            A.mixTarget = tg;
            A.mixTint = B ? wildLuts[B.i][0] : petGlowLut[0];
            if (B) {
                B.mixTarget = tg;
                B.mixTint = wildLuts[A.i][0];
            } else {
                petMixTarget = tg;
                petMixTint = wildLuts[A.i][0];
            }
        }
    }
    function wildTagNow() { wildStartTag(Date.now()); }       // IPC previews
    function wildMergeNow() { wildStartMerge(Date.now()); }

    // The mind of one wild swarm: picks a mode, then a target and a spring (stiffness k, damping c, top speed vmax), then moves.
    function wildBrain(sw, dt, now) {
        sw.fade += ((petHide ? 0 : 1) - sw.fade) * Math.min(1, dt * 3);
        // a wave of fright reaches it
        if (sw.pending && now >= sw.pending.at) {
            wildScare(sw, sw.pending.fx, sw.pending.fy, now);
            sw.pending = null;
        }
        // the cursor scares it, like it scares the pet, and starts a wave
        var cdx = sw.x - cx, cdy = sw.y - cy;
        if (sw.mode !== "panic" && Math.hypot(cdx, cdy) < petAvoid * 0.8) {
            wildScare(sw, cx, cy, now);
            wildWave(sw.x, sw.y, now, sw.i);
        }
        // which mode
        if (sw.mode !== "panic" || now > sw.panicUntil) {
            var want = "wander";
            if (petMode === "sleep")
                want = "sleep";
            else if (wildDrawing)
                want = "join";
            else if (wildMerge && (wildMerge.a === sw.i || wildMerge.b === sw.i))
                want = "merge";
            else if (wildTag && wildTag.chaser === sw.i)
                want = "chase";
            else if (wildTag && wildTag.runner === sw.i)
                want = "run";
            if (want !== sw.mode) {
                if (sw.mode === "join")
                    wildBurst(sw);   // the trick is over: burst
                sw.dvd = null;
                sw.mode = want;
                sw.next = 0;
            }
        }
        var k = 6, c = 5, vmax = 260;
        var moodWant = "";
        var mode = sw.mode;
        if (mode === "panic") {
            var fdx = sw.x - sw.fx, fdy = sw.y - sw.fy, fd = Math.max(1, Math.hypot(fdx, fdy));
            sw.tx = sw.x + fdx / fd * 260;
            sw.ty = sw.y + fdy / fd * 260;
            k = 40;
            c = 12;
            vmax = 650;
        } else if (mode === "sleep") {
            // sleep pile: curl up around the sleeping pet
            var sa = sw.i * 2.1 + 0.5;
            sw.tx = petPx + Math.cos(sa) * 55;
            sw.ty = petPy + Math.sin(sa) * 55;
            vmax = 320;
        } else if (mode === "join") {
            // join the trick: follow the path the pet drew a moment ago (one swarm behind the other); the second
            // swarm runs the mirror image of it in the shapes that have a direction
            if (petTrickKind === "dvd" && petDvd) {
                if (!sw.dvd) {   // its own bounce in the same box, from where it is, in another direction
                    sw.dvd = dvdMake({ x: petDvd.x0 - 24, y: petDvd.y0 - 24, w: petDvd.x1 - petDvd.x0 + 48, h: petDvd.y1 - petDvd.y0 + 48 }, sw.x, sw.y, 0);
                    sw.dvdT0 = now;
                }
                var wp = dvdAt(sw.dvd, (now - sw.dvdT0) / 1000);
                sw.tx = wp.x;
                sw.ty = wp.y;
                k = 400;   // rigid, no easing
                c = 40;
                vmax = 900;
                moodWant = "green";
            } else {
            var tw = now - (sw.i + 1) * 350;
            var h = petHist, q = h.length - 1;
            while (q > 0 && h[q].t > tw)
                q--;
            var jx = q >= 0 ? h[q].x : petPx, jy = q >= 0 ? h[q].y : petPy;
            if (sw.i === 1 && (petTrickKind === "loop" || petTrickKind === "eight" || petTrickKind === "clover")) {
                var dx = Math.cos(petTrickH), dy = Math.sin(petTrickH);
                var u = (jx - petTrickCX) * dx + (jy - petTrickCY) * dy;
                jx = 2 * (petTrickCX + u * dx) - jx;
                jy = 2 * (petTrickCY + u * dy) - jy;
            }
            sw.tx = jx;
            sw.ty = jy;
            k = 70;
            c = 16;
            vmax = 1800;
            moodWant = "green";
            }
        } else if (mode === "merge") {
            var mb = wildMerge.b >= 0 ? wild[wildMerge.b] : null;
            if (mb) {
                sw.tx = (sw.x + mb.x) / 2;
                sw.ty = (sw.y + mb.y) / 2;
            } else {
                sw.tx = petPx;
                sw.ty = petPy;
            }
            k = 10;
            c = 6;
            vmax = 320;
        } else if (mode === "chase") {
            var rn = wild[wildTag.runner];
            // faster than the runner, but erratic: the aim wobbles, and now and then it lunges sideways
            var wob = now / 1000 * 5 + sw.i * 3;
            sw.tx = rn.x + Math.cos(wob) * 35 + Math.cos(wob * 2.3) * 15;
            sw.ty = rn.y + Math.sin(wob * 1.3) * 35 + Math.sin(wob * 2.9) * 15;
            if (now > sw.next) {
                var la = Math.random() * 6.28;
                sw.vx += Math.cos(la) * 90;
                sw.vy += Math.sin(la) * 90;
                sw.next = now + 700 + Math.random() * 1100;
            }
            k = 26;
            c = 7;
            vmax = 780;
            moodWant = "red";
        } else if (mode === "run") {
            var ch = wild[wildTag.chaser];
            var rdx = sw.x - ch.x, rdy = sw.y - ch.y, rd = Math.max(1, Math.hypot(rdx, rdy));
            sw.tx = sw.x + rdx / rd * 300;
            sw.ty = sw.y + rdy / rd * 300;
            if (!petOnScreen(sw.tx, sw.ty)) {   // cornered: dodge toward the pet's side
                sw.tx = sw.x + (petPx - sw.x) * 0.6 - rdy / rd * 120;
                sw.ty = sw.y + (petPy - sw.y) * 0.6 + rdx / rd * 120;
            }
            k = 18;
            c = 8;
            vmax = 330;
            moodWant = "blue";
        } else {   // wander
            var dp = Math.hypot(sw.x - petPx, sw.y - petPy);
            if (dp > 420) {   // the leash: too far from the pet, come back
                sw.tx = petPx + (Math.random() - 0.5) * 300;
                sw.ty = petPy + (Math.random() - 0.5) * 300;
                sw.next = now + 2000;
            } else if (now > sw.next || Math.hypot(sw.tx - sw.x, sw.ty - sw.y) < 20) {
                wildPickTarget(sw, now);
            }
        }
        if (moodWant !== "")
            sw.moodKind = moodWant;
        sw.moodA += ((moodWant !== "" ? 1 : 0) - sw.moodA) * Math.min(1, dt * 8);
        sw.dim += ((mode === "sleep" ? 0.45 : 1) - sw.dim) * Math.min(1, dt * 3);
        var ax = (sw.tx - sw.x) * k - sw.vx * c;
        var ay = (sw.ty - sw.y) * k - sw.vy * c;
        // soft push-apart from the other swarms (not while they do something together)
        if (mode === "wander" || mode === "panic") {
            var others = [{ x: petPx, y: petPy }];
            for (var o = 0; o < wild.length; o++)
                if (wild[o] !== sw)
                    others.push(wild[o]);
            for (var oi = 0; oi < others.length; oi++) {
                var sx = sw.x - others[oi].x, sy = sw.y - others[oi].y, sd = Math.hypot(sx, sy);
                if (sd < 110 && sd > 0.5) {
                    ax += sx / sd * (110 - sd) * 8;
                    ay += sy / sd * (110 - sd) * 8;
                }
            }
        }
        sw.vx += ax * dt;
        sw.vy += ay * dt;
        var sp = Math.hypot(sw.vx, sw.vy);
        if (sp > vmax) {
            sw.vx *= vmax / sp;
            sw.vy *= vmax / sp;
        }
        var nx = sw.x + sw.vx * dt, ny = sw.y + sw.vy * dt;
        if (!petOnScreen(nx, ny)) {   // never leave the screens: bounce back
            sw.vx *= -0.5;
            sw.vy *= -0.5;
            nx = sw.x;
            ny = sw.y;
        }
        sw.x = nx;
        sw.y = ny;
    }

    // The lights of one wild swarm: the same spring-and-orbit life as the pet's lights (see stepSwarm in Layer).
    // While it joins a trick the lights spread along the swarm's own recent path, so each swarm traces the shape too.
    function wildLights(sw, dt, now) {
        var fl = sw.flies;
        var join = sw.mode === "join";
        var h = sw.hist;
        if (h.length === 0 || now - h[h.length - 1].t >= 12)
            h.push({ x: sw.x, y: sw.y, t: now });
        while (h.length > 0 && now - h[0].t > 5000)
            h.shift();
        sw.shape += ((join && petTrickKind !== "dvd" ? 1 : 0) - sw.shape) * Math.min(1, dt * (join ? 6 : 12));
        sw.scat += ((sw.mode === "panic" ? 1 : 0) - sw.scat) * Math.min(1, dt * (sw.mode === "panic" ? 14 : 3));
        sw.boom = Math.max(0, sw.boom - dt / 0.6);
        sw.mixA += (sw.mixTarget - sw.mixA) * Math.min(1, dt * 6);
        var spd = Math.hypot(sw.vx, sw.vy);
        var rest = 12 + sw.scat * 80 + Math.min(40, spd * 0.04);
        var t = now / 1000;
        var nf = fl.length;
        var span = petLife * 0.85;
        if (petTrickCycle > 0)
            span = Math.min(span, petTrickCycle * (nf - 1) / nf);
        for (var j = 0; j < nf; j++) {
            var f = fl[j];
            var ox = Math.cos(f.ph + t * f.w) * rest * f.r - sw.vx * 0.03 * (0.5 + j * 0.12);
            var oy = Math.sin(f.ph + t * f.w * 1.1) * rest * f.r - sw.vy * 0.03 * (0.5 + j * 0.12);
            var gx = sw.x + ox, gy = sw.y + oy;
            if (sw.shape > 0.01 && h.length > 1) {
                var want = now - (j / (nf - 1)) * span;
                var q = h.length - 1;
                while (q > 0 && h[q].t > want)
                    q--;
                gx += (h[q].x - gx) * sw.shape;
                gy += (h[q].y - gy) * sw.shape;
            }
            var kk = 60 + 90 * sw.shape, cc = 8 + 8 * sw.shape;
            if (join && petTrickKind === "dvd") {
                kk = 320;
                cc = 32;
            }
            kk += (12 - kk) * sw.boom;
            cc += (4 - cc) * sw.boom;
            f.vx += ((gx - f.x) * kk - f.vx * cc) * dt;
            f.vy += ((gy - f.y) * kk - f.vy * cc) * dt;
            f.x += f.vx * dt;
            f.y += f.vy * dt;
        }
    }

    // hintd (SUPER+d daemon): "boxes live" lists clickable things of the focused window; it clicks nothing.
    Process {
        id: petPokeQ
        command: ["bash", "-c", "printf 'boxes live\\n' | timeout 4 socat -t3 - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock"]
        stdout: SplitParser {
            onRead: data => {
                if (data.length > 0 && root.petPokeLines.length < 400)
                    root.petPokeLines = root.petPokeLines.concat([data]);
            }
        }
        onRunningChanged: if (!running) root.petPokePick()
    }

    Process {
        id: petPokeClick
    }

    Process {
        running: root.onAC
        command: ["mmsg", "watch", "keymode"]
        stdout: SplitParser {
            onRead: data => root.onKeymode(data)
        }
    }

    function fxEnd(e) {
        if (e.endT)
            return;
        e.endT = Date.now();
        e.dur = (e.endT - e.t) + 300;   // fade out for 300 ms, then it expires
        fxSeq++;
    }

    // ---- Fullscreen sweep, workspace wash, floating rings, resize edge, layout gaps, monitor connect ----
    property var prevMons: ({})
    property real lastLayoutT: 0
    property real lastTagT: 0
    property var gapsPending: []
    property var knownScreens: []
    property var screenQueue: []

    Process {
        running: root.onAC
        command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser {
            onRead: data => root.onMonitors(data)
        }
        onRunningChanged: if (!running) root.prevMons = ({})
    }

    Timer {
        id: gapsDelay
        interval: 450   // let the tiles finish moving, then light the gaps between them
        onTriggered: {
            var l = root.gapsPending;
            root.gapsPending = [];
            for (var i = 0; i < l.length; i++)
                root.fxGaps(l[i]);
        }
    }

    Timer {
        id: screenDelay
        interval: 300   // the overlay window of the new screen appears first
        onTriggered: {
            var l = root.screenQueue;
            root.screenQueue = [];
            for (var i = 0; i < l.length; i++)
                root.fxPlug(l[i]);
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            var names = [];
            var fresh = [];
            for (var i = 0; i < Quickshell.screens.length; i++) {
                var nm = Quickshell.screens[i].name;
                names.push(nm);
                if (root.knownScreens.indexOf(nm) < 0)
                    fresh.push(nm);
            }
            root.knownScreens = names;
            if (fresh.length > 0 && root.onAC && Date.now() - root.startT > 3000) {
                root.screenQueue = fresh;
                screenDelay.restart();
            }
        }
    }

    function onMonitors(line) {
        var o;
        try {
            o = JSON.parse(line);
        } catch (err) {
            return;
        }
        if (!o || !o.monitors)
            return;
        var cur = {};
        var now = Date.now();
        for (var i = 0; i < o.monitors.length; i++) {
            var m = o.monitors[i];
            var tags = m.active_tags || [];
            var mm = { name: m.name, layout: m.layout_symbol, tags: tags.join(","), first: tags.length > 0 ? tags[0] : 0,
                       x: m.x, y: m.y, w: m.width, h: m.height };
            cur[m.name] = mm;
            var p = prevMons[m.name];
            if (!p) {
                if (monsInit)
                    petNewScreen(m.name);   // a screen was plugged in: the pet explores it
                continue;
            }
            if (p.tags !== mm.tags) {
                lastTagT = now;
            } else if (p.layout !== mm.layout) {
                lastLayoutT = now;
            }
        }
        prevMons = cur;
        monsInit = true;
    }

    // ---- Volume and brightness bars. Checked once after key presses (mango sends no event for them). ----
    property real lastVol: -1
    property bool lastMute: false
    property real lastBri: -1
    property real briMax: 0

    FileView {
        id: briMaxFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        onLoaded: root.briMax = parseInt(text())
    }

    FileView {
        id: briFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        onLoaded: root.onBri(parseInt(text()))
    }

    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => root.onVol(data)
        }
    }

    function onVol(line) {
        var m = line.match(/Volume:\s*([0-9.]+)/);
        if (!m)
            return;
        var v = parseFloat(m[1]);
        var mute = line.indexOf("MUTED") >= 0;
        if (lastVol >= 0 && (Math.abs(v - lastVol) > 0.001 || mute !== lastMute))
            fxLevel("vol", v, mute);
        lastVol = v;
        lastMute = mute;
    }

    function onBri(raw) {
        if (briMax <= 0 || isNaN(raw))
            return;
        var v = raw / briMax;
        if (lastBri >= 0 && Math.abs(v - lastBri) > 0.002)
            fxLevel("bri", v, false);
        lastBri = v;
    }

    function fxLevel(lk, val, muted) {
        var name = mon;
        var m = prevMons[name];
        if (!m) {
            if (Quickshell.screens.length === 0)
                return;
            var s0 = Quickshell.screens[0];
            name = s0.name;
            m = { x: s0.x, y: s0.y, w: s0.width, h: s0.height };
        }
        var now = Date.now();
        for (var i = 0; i < fxList.length; i++) {
            var o = fxList[i];
            if (o.kind === "level" && o.lk === lk && o.mon === name && now - o.t < o.dur) {
                o.pv = o.pv + (o.val - o.pv) * Math.min(1, (now - o.ut) / 160);
                o.val = val;
                o.muted = muted;
                o.ut = now;
                o.t = now;   // keep it up a little longer
                fxSeq++;
                return;
            }
        }
        var e = { kind: "level", lk: lk, mon: name, x: m.x, y: m.y, w: m.w, h: m.h, val: val, pv: val, muted: muted, ut: now, dur: 1500 };
        fxBounds(e, [m], 0);
        fxAdd(e);
    }

    // ---- A notification arrived: the top-left corner glows once. The notification daemon is the bar
    // (quickshell -c bar); we only watch the DBus call, event-driven. dbus-monitor prints the message text,
    // but only the line that names the call is looked at, and nothing is stored. ----
    Process {
        running: root.onAC
        command: ["dbus-monitor", "--session", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
        stdout: SplitParser {
            onRead: data => {
                if (data.indexOf("member=Notify") >= 0) {
                    root.petCurious();
                    root.fxNotify();
                    remapWait.restart();
                }
            }
        }
    }

    // The bar shows its notification window (also on the Overlay layer) by mapping it anew, and a newly mapped surface lands
    // on top of the older ones, so the notification would cover the cursor effects. After it is up, hide our windows for a
    // moment and show them again: they are the newest then, so they draw above it. Nothing is lost (only the surface is re-made).
    property bool remapGap: false
    Timer {
        id: remapWait
        interval: 450
        onTriggered: {
            root.remapGap = true;
            remapBack.restart();
        }
    }
    Timer {
        id: remapBack
        interval: 80
        onTriggered: root.remapGap = false
    }

    function fxNotify() {
        var name = mon;
        var m = prevMons[name];
        if (!m) {
            if (Quickshell.screens.length === 0)
                return;
            var s0 = Quickshell.screens[0];
            name = s0.name;
            m = { x: s0.x, y: s0.y, w: s0.width, h: s0.height };
        }
        var e = { kind: "notify", mon: name, x: m.x, y: m.y, w: m.w, h: m.h, dur: 1100 };
        fxBounds(e, [m], 0);
        fxAdd(e);
    }

    function withAlpha(col, a) {
        return col.replace("rgb(", "rgba(").replace(")", "," + a + ")");
    }

    function fxSweep(n, dir) {
        var e = { kind: "sweep", cid: n.id, mon: n.mon, dir: dir, dur: 700, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [n], 20);
        fxAdd(e);
    }

    function fxFloat(n, dir) {
        var e = { kind: "float", cid: n.id, mon: n.mon, dir: dir, dur: 800, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [n], 60);
        fxAdd(e);
    }

    function fxWash(m, dir) {
        var e = { kind: "wash", mon: m.name, dir: dir, dur: 600, x: m.x, y: m.y, w: m.w, h: m.h };
        fxBounds(e, [m], 0);
        fxAdd(e);
    }

    function fxGaps(name) {
        var tiles = [];
        for (var id in prevClients)
            if (prevClients[id].vis && prevClients[id].mon === name)
                tiles.push(prevClients[id]);
        var lines = [];
        for (var i = 0; i < tiles.length; i++)
            for (var j = i + 1; j < tiles.length; j++) {
                var g = gapLine(tiles[i], tiles[j]);
                if (g)
                    lines.push(g);
            }
        if (lines.length === 0)
            return;
        var e = { kind: "gaps", mon: name, lines: lines, dur: 700 };
        var rects = [];
        for (var k = 0; k < lines.length; k++)
            rects.push({ x: Math.min(lines[k].x1, lines[k].x2), y: Math.min(lines[k].y1, lines[k].y2),
                         w: Math.abs(lines[k].x2 - lines[k].x1), h: Math.abs(lines[k].y2 - lines[k].y1) });
        fxBounds(e, rects, 30);
        fxAdd(e);
    }

    // A tile being resized by its border: the edges that move glow while it goes on, then fade.
    function fxResizeCheck(list, setChanged) {
        var now = Date.now();
        if (setChanged || list.length < 1 || list.length > 3 || now - lastLayoutT < 900 || now - lastTagT < 900)
            return;
        for (var i = 0; i < list.length; i++) {
            var p = list[i].p, n = list[i].n;
            if (!n.foc || Math.abs(n.w - p.w) + Math.abs(n.h - p.h) < 2)
                continue;
            var l = Math.abs(n.x - p.x) > 1, r = Math.abs((n.x + n.w) - (p.x + p.w)) > 1;
            var t = Math.abs(n.y - p.y) > 1, b = Math.abs((n.y + n.h) - (p.y + p.h)) > 1;
            if ((l && r) || (t && b) || !(l || r || t || b))
                continue;   // both sides moved: that is a move or a swap, not a resize
            var e = fxAlive("resize", n.id);
            if (e) {
                e.edges = { l: e.edges.l || l, r: e.edges.r || r, t: e.edges.t || t, b: e.edges.b || b };
                e.dur = (now - e.t) + 400;
                fxRetarget(e, n);
            } else {
                e = { kind: "resize", cid: n.id, mon: n.mon, dur: 400, x: n.x, y: n.y, w: n.w, h: n.h,
                      edges: { l: l, r: r, t: t, b: b } };
                fxBounds(e, [n], 40);
                fxAdd(e);
            }
        }
    }

    function onKeymode(line) {
        var mode = "default";
        try {
            mode = JSON.parse(line).keymode;
        } catch (err) {
            return;
        }
        for (var i = 0; i < fxList.length; i++)
            if (fxList[i].kind === "keymode" && !fxList[i].endT)
                fxEnd(fxList[i]);
        if (mode && mode !== "default") {
            var e = { kind: "keymode", mon: "*", mode: mode, hold: true, dur: 1e12 };
            fxBounds(e, [{ x: -1e5, y: -1e5, w: 2e5, h: 2e5 }], 0);
            fxAdd(e);
        }
    }

    function fxPlug(mon) {
        var e = { kind: "plug", mon: mon || "*", dur: 1500 };
        fxBounds(e, [{ x: -1e5, y: -1e5, w: 2e5, h: 2e5 }], 0);
        fxAdd(e);
    }

    function fxUrgent(n) {
        petUrgent(n);
        var e = { kind: "urgent", cid: n.id, mon: n.mon, dur: 1e12, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [n], 40);
        fxAdd(e);
    }

    function fxHop(a, b) {
        var e = { kind: "hop", mon: "*", dur: 380, ax: a.x + a.w / 2, ay: a.y + a.h / 2, bx: b.x + b.w / 2, by: b.y + b.h / 2 };
        fxBounds(e, [{ x: Math.min(e.ax, e.bx), y: Math.min(e.ay, e.by),
                       w: Math.abs(e.ax - e.bx), h: Math.abs(e.ay - e.by) }], 150);
        fxAdd(e);
    }

    function holdEnv(e, now) {
        var fin = Math.min(1, (now - e.t) / 250);
        var fout = e.endT ? Math.max(0, 1 - (now - e.endT) / 300) : 1;
        return fin * fout;
    }

    // ---- Swap / move effects: five candidates to compare ----
    //   1 lit while moving   2 landing flash   3 swap link   4 gap shimmer   5 squash rim
    property int moveFx: 26           // used for real tile moves: digits of the effects to play, e.g. 345; 0 = none
    property int demoStep: 0
    property bool fxFreeze: false


    IpcHandler {
        target: "fx"
        // A touch hold is about to become a right click (touch-gestures/rclick.sh calls this first).
        // x, y: global screen pixels, as in `mmsg get cursorpos`. Draws the right-click ripple (square)
        // there and, for 300 ms, keeps the mouse trail from drawing the pointer's walk to the finger.
        function hold(x: int, y: int): void {
            for (var i = 0; i < Quickshell.screens.length; i++) {
                var s = Quickshell.screens[i];
                if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) {
                    root.holdUntil = Date.now() + 300;
                    root.clickShape = "square";
                    root.clickX = x;
                    root.clickY = y;
                    root.clickMon = s.name;
                    root.clicks++;
                    return;
                }
            }
        }
        function play(n: int): void {   // play effect n on the focused tile now; 0 = all five in turn
            if (n === 0) {
                root.demoStep = 1;
                root.fxDemo(1);
                demoTimer.restart();
            } else {
                root.fxDemo(n);
            }
        }
        function peak(n: int): void {   // freeze effect n at its strongest moment for 3 s (for screenshots)
            root.fxFreeze = true;
            root.fxDemo(n);
            root.fxFreeze = false;
        }
        function rebuild(): void {   // test: destroy and recreate the overlay windows (what plug-in does)
            root.overlayOn = false;
            rebuildT.start();
        }
        function wow(kind: string): void {   // preview: sweep, float, wash, gaps, resize, monitor on the focused tile / its screen
            for (var id in root.prevClients) {
                var c = root.prevClients[id];
                if (!(c.vis && c.foc))
                    continue;
                if (kind === "notify") root.fxNotify();
                else if (kind === "level") { root.fxLevel("vol", 0.35, false); root.fxLevel("vol", 0.7, false); root.fxLevel("bri", 0.5, false); }
                else if (kind === "implode") root.fxImplode(c);
                else if (kind === "spray") root.fxSpray({ id: c.id, mon: c.mon, x: c.x - 320, y: c.y, w: c.w, h: c.h }, c);
                else if (kind === "sweep") root.fxSweep(c, 1);
                else if (kind === "float") root.fxFloat(c, 1);
                else if (kind === "sink") root.fxFocus(c, null);
                else if (kind === "wash" && root.prevMons[c.mon]) root.fxWash(root.prevMons[c.mon], 1);
                else if (kind === "gaps") root.fxGaps(c.mon);
                else if (kind === "monitor") root.fxPlug(c.mon);
                else if (kind === "resize") {
                    var e = { kind: "resize", cid: c.id, mon: c.mon, dur: 1500, x: c.x, y: c.y, w: c.w, h: c.h,
                              edges: { l: false, r: true, t: false, b: false } };
                    root.fxBounds(e, [c], 40);
                    root.fxAdd(e);
                }
            }
        }
        function urgent(secs: int): void {   // preview: the focused tile breathes red for N seconds
            for (var id in root.prevClients) {
                var c = root.prevClients[id];
                if (c.vis && c.foc) {
                    root.fxUrgent(c);
                    var l = root.fxList;
                    l[l.length - 1].fake = true;
                    urgDemo.restart();
                    urgDemo.interval = Math.max(1, secs) * 1000;
                }
            }
        }
        function move(n: int): void {   // choose the effect used for real moves (0 = none)
            root.moveFx = n;
        }
        function petinfo(): string {   // pet state, for debugging
            return "on=" + root.petOn + " mode=" + root.petMode + " pos=" + Math.round(root.petX) + "," + Math.round(root.petY) + " seq=" + root.petSeq + " hide=" + root.petHide + " behind=" + root.petBehind + " fade=" + root.petFade.toFixed(2) +" energy=" + root.petEnergy().toFixed(2) + " poke=" + root.petPokePhase + " lines=" + root.petPokeLines.length + " asked=" + root.petPokeAsked + " cand=" + root.petPokeCand + " next=" + Math.round((root.petPokeNext - Date.now()) / 1000);
        }
        function swarminfo(): string {   // the wild swarms, for debugging
            var out = "flocks=" + root.swarmFlocks + " wild=" + root.wild.length + " seq=" + root.wildSeq;
            for (var i = 0; i < root.wild.length; i++) {
                var s = root.wild[i];
                out += " | #" + i + " " + s.mode + " pos=" + Math.round(s.x) + "," + Math.round(s.y) + " v=" + Math.round(Math.hypot(s.vx, s.vy)) + " fade=" + s.fade.toFixed(2);
            }
            return out;
        }
        function pet(kind: string): void {   // preview the pet: type, notify, plug, flee
            if (kind === "type") root.petKey();
            else if (kind === "notify") root.petCurious();
            else if (kind === "plug") root.petSpawn();
            else if (kind === "flee") root.petFlee();
            else if (kind === "hide") root.petGo("hide");
            else if (kind === "sleep") root.petGo("sleep");
            else if (kind === "dare") root.petGo("dare");
            else if (kind === "ripple") root.petRipple(1.4);
            else if (kind === "burst") root.petBurstNow();
            else if (kind === "lap") { root.petLapMon = ""; root.petLapSpd = 0.5; root.petGo("lap"); }
            else if (kind.indexOf("trick") === 0) { root.petTrickForce = kind.indexOf(":") > 0 ? kind.split(":")[1] : ""; root.petGo("trick"); }
            else if (kind === "screen") root.petNewScreen(root.mon);
            else if (kind === "peek") root.petGo("peek");
            else if (kind === "startle") root.petApply("startle");
            else if (kind === "tag") root.wildTagNow();
            else if (kind === "merge") root.wildMergeNow();
            else if (kind === "panic") root.wildPanicNow();
            else if (kind === "poke") root.petPokeAsk();   // asks hintd; WARNING: really clicks if something is found
        }
    }

    Timer {
        id: demoTimer
        interval: 1500
        repeat: true
        onTriggered: {
            root.demoStep++;
            if (root.demoStep > 5) {
                running = false;
                return;
            }
            root.fxDemo(root.demoStep);
        }
    }

    function fxDemo(n) {
        var a = null, b = null, all = [];
        for (var id in prevClients) {
            var c = prevClients[id];
            if (c.vis && c.foc)
                a = c;
        }
        if (!a)
            return;
        for (var id2 in prevClients) {
            var d = prevClients[id2];
            if (!d.vis || d.mon !== a.mon)
                continue;
            all.push(d);
            if (n === 4) {
                if (d.id !== a.id && gapLine(a, d) && (!b || d.w * d.h > b.w * b.h))
                    b = d;
            } else if (d.id !== a.id && (!b || d.w * d.h > b.w * b.h)) {
                b = d;
            }
        }
        fxMoveFx(n, a, a, b, b, all);
    }

    // The middle line of the gap between two neighbouring tiles, or null if they do not touch.
    function gapLine(a, b) {
        var v0 = Math.max(a.y, b.y), v1 = Math.min(a.y + a.h, b.y + b.h);
        if (v1 - v0 > 10) {
            var g1 = b.x - (a.x + a.w), g2 = a.x - (b.x + b.w);
            if (g1 >= -2 && g1 <= 40) return { x1: a.x + a.w + g1 / 2, y1: v0, x2: a.x + a.w + g1 / 2, y2: v1 };
            if (g2 >= -2 && g2 <= 40) return { x1: b.x + b.w + g2 / 2, y1: v0, x2: b.x + b.w + g2 / 2, y2: v1 };
        }
        var h0 = Math.max(a.x, b.x), h1 = Math.min(a.x + a.w, b.x + b.w);
        if (h1 - h0 > 10) {
            var k1 = b.y - (a.y + a.h), k2 = a.y - (b.y + b.h);
            if (k1 >= -2 && k1 <= 40) return { x1: h0, y1: a.y + a.h + k1 / 2, x2: h1, y2: a.y + a.h + k1 / 2 };
            if (k2 >= -2 && k2 <= 40) return { x1: h0, y1: b.y + b.h + k2 / 2, x2: h1, y2: b.y + b.h + k2 / 2 };
        }
        return null;
    }

    function sameRect(a, b, tol) {
        return Math.abs(a.x - b.x) + Math.abs(a.y - b.y) + Math.abs(a.w - b.w) + Math.abs(a.h - b.h) <= tol;
    }

    // pa -> na: tile A before / after. pb -> nb: a second tile (effect 3). all: visible tiles (effect 4).
    function fxMoveFx(mode, pa, na, pb, nb, all) {
        var e = { kind: "mv" + mode, cid: na.id, mon: na.mon, dur: (mode === 2) ? 600 : 700,
                  x: na.x, y: na.y, w: na.w, h: na.h, fx: pa.x, fy: pa.y, fw: pa.w, fh: pa.h };
        if (!sameRect(pa, na, 0))
            e.mt = Date.now();   // the tile is really moving: follow it
        var rects = [pa, na];
        if (mode === 3) {
            if (!nb || !pb)
                return;
            e.eb = { x: nb.x, y: nb.y, w: nb.w, h: nb.h, fx: pb.x, fy: pb.y, fw: pb.w, fh: pb.h, mt: e.mt };
            rects.push(pb);
            rects.push(nb);
        }
        if (mode === 4) {
            if (!nb || !pb)
                return;
            e.gap = gapLine(na, nb);
            if (!e.gap)
                return;   // the two tiles are not neighbours: no gap to light
            rects.push(pb);
            rects.push(nb);
        }
        fxBounds(e, rects, 40);
        if (fxFreeze) {
            e.freeze = true;
            e.dur = 3000;
        }
        fxAdd(e);
    }

    // Real moves: moved = [{p: before, n: after}], cur = all clients now.
    function fxMoves(moved, cur) {
        var digits = String(moveFx).split("");
        for (var di = 0; di < digits.length; di++)
            fxMovesOne(parseInt(digits[di]), moved, cur);
    }

    function fxMovesOne(m, moved, cur) {
        if (m < 1 || m > 6)
            return;
        if (m === 6) {   // spray: sparks leave the leading edge of every tile that moved
            for (var si = 0; si < moved.length; si++)
                if (moved[si].n.foc)   // only the focused tile
                    fxSpray(moved[si].p, moved[si].n);
            return;
        }
        if (m === 3 || m === 4) {
            for (var i = 0; i < moved.length; i++)
                for (var j = i + 1; j < moved.length; j++)
                    if (sameRect(moved[i].n, moved[j].p, 40) && sameRect(moved[j].n, moved[i].p, 40))
                        fxMoveFx(m, moved[i].p, moved[i].n, moved[j].p, moved[j].n, null);
        } else {
            for (var k = 0; k < moved.length; k++)
                if (m !== 2 || moved[k].n.foc)   // the landing flash is only for the focused tile
                fxMoveFx(m, moved[k].p, moved[k].n, null, null, null);
        }
    }

    // Sparks fly off the edge that leads the move, along the move's direction.
    function fxSpray(pa, na) {
        var dx = (na.x + na.w / 2) - (pa.x + pa.w / 2);
        var dy = (na.y + na.h / 2) - (pa.y + pa.h / 2);
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 1)
            return;
        var ux = dx / len, uy = dy / len;
        var horiz = Math.abs(dx) >= Math.abs(dy);
        var e = { kind: "spray", cid: na.id, mon: na.mon, dur: 1100, parts: [] };
        for (var i = 0; i < 46; i++) {
            var ts = Math.random() * 60;   // at once, at the target spot
            var k = 1;
            var rx = pa.x + (na.x - pa.x) * k, ry = pa.y + (na.y - pa.y) * k;
            var rw = pa.w + (na.w - pa.w) * k, rh = pa.h + (na.h - pa.h) * k;
            var along = Math.random();
            var px, py;
            if (horiz) {
                px = dx > 0 ? rx + rw : rx;
                py = ry + 8 + along * Math.max(1, rh - 16);
            } else {
                py = dy > 0 ? ry + rh : ry;
                px = rx + 8 + along * Math.max(1, rw - 16);
            }
            var sp = 70 + Math.random() * 150;
            e.parts.push({ ts: ts, x: px, y: py, vx: ux * sp + (Math.random() - 0.5) * 50, vy: uy * sp + (Math.random() - 0.5) * 50,
                           life: 350 + Math.random() * 450, s: 0.5 + Math.random() * 1.3, c: Math.random() });
        }
        fxBounds(e, [pa, na], 220);
        fxAdd(e);
    }

    function fxBounds(e, rects, pad) {
        var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (var i = 0; i < rects.length; i++) {
            x0 = Math.min(x0, rects[i].x);
            y0 = Math.min(y0, rects[i].y);
            x1 = Math.max(x1, rects[i].x + rects[i].w);
            y1 = Math.max(y1, rects[i].y + rects[i].h);
        }
        e.bx0 = x0 - pad;
        e.by0 = y0 - pad;
        e.bx1 = x1 + pad;
        e.by1 = y1 + pad;
    }

    // ---- effect switches (effects.conf) ----
    property var fxSwitch: null   // null until effects.conf is read = all on
    property real pokeMin: 25     // `annoying` wait between clicks, seconds (effects.conf: pokeinterval MIN MAX)
    property real pokeMax: 60
    function fxOn(name) { return fxSwitch === null || fxSwitch[name] === true; }
    readonly property var fxGroup: ({ focus: "focus", open: "open", implode: "close", close: "close", mv: "swap", spray: "swap", ghost: "swap", notify: "notify", sweep: "fullscreen", float: "floating", urgent: "urgent", plug: "plug", keymode: "keymode", resize: "resize" })
    FileView {
        id: confFile
        path: Quickshell.shellDir + "/effects.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var m = {}, ls = text().split("\n");
            var pmin = 25, pmax = 60;
            for (var i = 0; i < ls.length; i++) {
                var mm = /^\s*([a-z]+)(\s|$)/.exec(ls[i]);
                if (mm) m[mm[1]] = true;
                var pi = /^\s*pokeinterval\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)/.exec(ls[i]);
                if (pi) { pmin = Math.max(1, +pi[1]); pmax = Math.max(pmin, +pi[2]); }
            }
            root.pokeMin = pmin;
            root.pokeMax = pmax;
            root.fxSwitch = m;
        }
    }

    function fxAdd(e) {
        var g = fxGroup[e.kind];
        if (g !== undefined && !fxOn(g)) return;
        var now = Date.now();
        e.t = now;
        var keep = [];
        for (var i = 0; i < fxList.length; i++)
            if (now - fxList[i].t < fxList[i].dur)
                keep.push(fxList[i]);
        keep.push(e);
        fxList = keep;
        fxSeq++;
    }

    // Sparkles for a tile: "open" = from the four corners outward, "close" = off the edges.
    function fxBurst(e, mode) {
        var parts = [];
        var cx0 = e.x + e.w / 2, cy0 = e.y + e.h / 2;
        var corner = [-Math.PI * 0.75, -Math.PI * 0.25, Math.PI * 0.25, Math.PI * 0.75];   // TL TR BR BL
        for (var i = 0; i < 44; i++) {
            var px, py, ang;
            if (mode === "open") {
                var cc = i % 4;
                px = e.x + ((cc === 1 || cc === 2) ? e.w : 0);
                py = e.y + (cc >= 2 ? e.h : 0);
                ang = corner[cc] + (Math.random() - 0.5) * 1.2;
            } else {
                var side = Math.floor(Math.random() * 4);
                var tt = Math.random();
                px = (side === 0) ? e.x + tt * e.w : (side === 1) ? e.x + e.w : (side === 2) ? e.x + tt * e.w : e.x;
                py = (side === 0) ? e.y : (side === 1) ? e.y + tt * e.h : (side === 2) ? e.y + e.h : e.y + tt * e.h;
                ang = Math.atan2(py - cy0, px - cx0) + (Math.random() - 0.5) * 0.8;
            }
            var sp = 30 + Math.random() * 110;
            parts.push({ x: px, y: py, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
                         life: 450 + Math.random() * 450, s: 1.2 + Math.random() * 1.8, cf: Math.random() });
        }
        e.parts = parts;
    }

    function fxAlive(kind, cid) {
        var now = Date.now();
        for (var i = 0; i < fxList.length; i++)
            if (fxList[i].kind === kind && fxList[i].cid === cid && !fxList[i].endT && now - fxList[i].t < fxList[i].dur)
                return fxList[i];
        return null;
    }

    function fxOpen(n) {
        var e = { kind: "open", cid: n.id, mon: n.mon, dur: 900, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [n], 150);
        fxAdd(e);
    }

    // A closed tile: its outline collapses into its centre and a small flash ends it.
    function fxImplode(n) {
        var e = { kind: "implode", mon: n.mon, dur: 260, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [n], 40);
        fxAdd(e);
    }

    function fxClose(n) {
        var e = { kind: "close", cid: n.id, mon: n.mon, dur: 900, x: n.x, y: n.y, w: n.w, h: n.h };
        fxBurst(e, "close");
        fxBounds(e, [n], 150);
        fxAdd(e);
    }

    // The rectangle a focus effect shows now. A tile that is still resizing or moving is followed:
    // the effect glides from the old rectangle to the new one like the tile does (~500 ms).
    // The compositor's own move curve (animation_curve_move=0.05,1.2,0.2,1, 500 ms), including
    // its small overshoot, so the effect stays on the real tile.
    function moveCurve(m) {
        if (m <= 0) return 0;
        if (m >= 1) return 1;
        var lo = 0, hi = 1, t = 0.5;
        for (var i = 0; i < 24; i++) {   // solve x(t) = m
            t = (lo + hi) / 2;
            var u = 1 - t;
            var x = 3 * u * u * t * 0.05 + 3 * u * t * t * 0.2 + t * t * t;
            if (x < m) lo = t; else hi = t;
        }
        var v = 1 - t;
        return 3 * v * v * t * 1.2 + 3 * v * t * t * 1.0 + t * t * t;
    }

    function fxRect(e, now) {
        if (e.mt === undefined)
            return { x: e.x, y: e.y, w: e.w, h: e.h };
        var k = moveCurve((now - e.mt) / 500);
        return { x: e.fx + (e.x - e.fx) * k, y: e.fy + (e.y - e.fy) * k,
                 w: e.fw + (e.w - e.fw) * k, h: e.fh + (e.h - e.fh) * k };
    }

    function fxFocus(n, p) {
        if (fxAlive("open", n.id))
            return;   // a new window already gets its own burst
        var e = { kind: "focus", cid: n.id, mon: n.mon, dur: 900, x: n.x, y: n.y, w: n.w, h: n.h };
        var rects = [n];
        if (p && (p.x !== n.x || p.y !== n.y || p.w !== n.w || p.h !== n.h)) {
            // the tile is about to change size: start from where it is now
            e.fx = p.x; e.fy = p.y; e.fw = p.w; e.fh = p.h;
            e.mt = Date.now();
            rects.push(p);
        }
        fxBounds(e, rects, 40);
        fxAdd(e);
    }

    function fxRetarget(e, n) {
        var now = Date.now();
        var cur = fxRect(e, now);
        e.fx = cur.x; e.fy = cur.y; e.fw = cur.w; e.fh = cur.h;
        e.x = n.x; e.y = n.y; e.w = n.w; e.h = n.h;
        e.mt = now;
        fxBounds(e, [{ x: e.fx, y: e.fy, w: e.fw, h: e.fh }, n], 40);
        fxSeq++;
    }

    function fxGhost(p, n) {
        var g = fxAlive("ghost", n.id);
        if (g) {   // still moving: just retarget the running echo
            g.x = n.x; g.y = n.y; g.w = n.w; g.h = n.h;
            fxBounds(g, [{ x: g.fx, y: g.fy, w: g.fw, h: g.fh }, n], 20);
            fxSeq++;
            return;
        }
        var e = { kind: "ghost", cid: n.id, mon: n.mon, dur: 650, fx: p.x, fy: p.y, fw: p.w, fh: p.h,
                  x: n.x, y: n.y, w: n.w, h: n.h };
        fxBounds(e, [p, n], 20);
        fxAdd(e);
    }

    function onClients(line) {
        var o;
        try {
            // window titles can be huge and change often: cut them out before parsing
            o = JSON.parse(line.replace(/"title":"(?:[^"\\]|\\.)*",/, ""));
        } catch (err) {
            return;
        }
        if (!o || !o.clients)
            return;
        var cur = {};
        for (var i = 0; i < o.clients.length; i++) {
            var c = o.clients[i];
            if (c.width <= 0 || c.height <= 0 || c.is_minimized)
                continue;
            cur[c.id] = { id: c.id, mon: c.monitor, x: c.x, y: c.y, w: c.width, h: c.height,
                          vis: !!c.is_visible, foc: !!c.is_focused, urg: !!c.is_urgent, fs: !!c.is_fullscreen, fl: !!c.is_floating };
        }
        var moved = [];
        var resized = [];
        var setChanged = false;
        if (clientsInit) {
            for (var id in cur) {
                var n = cur[id];
                var p = prevClients[id];
                if (!p) {
                    setChanged = true;
                    if (n.vis)
                        fxOpen(n);
                } else {
                    var changed = Math.abs(n.x - p.x) + Math.abs(n.y - p.y) + Math.abs(n.w - p.w) + Math.abs(n.h - p.h) > 0;
                    if (n.vis && p.vis && n.fs !== p.fs)
                        fxSweep(n, n.fs ? 1 : -1);
                    if (n.vis && p.vis && n.fl !== p.fl) {
                        if (n.fl)
                            fxFloat(n, 1);
                        else
                            fxFocus(n, p);   // back to tile: same glow as focus
                    }
                    if (n.vis && p.vis && n.fl && !p.fl)
                        petPerch(n);
                    if (changed && n.vis && p.vis && p.mon === n.mon)
                        resized.push({ p: p, n: n });
                    var fe = fxAlive("focus", n.id);
                    if (fe && changed)
                        fxRetarget(fe, n);   // the focused tile is still being resized
                    else if (n.vis && n.foc && !p.foc) {
                        fxFocus(n, p);
                    }
                    if (moveFx > 0 && n.vis && p.vis && p.mon === n.mon
                            && Math.abs(n.x - p.x) + Math.abs(n.y - p.y) + Math.abs(n.w - p.w) + Math.abs(n.h - p.h) > 24)
                        moved.push({ p: p, n: n });
                }
            }
            for (var pid in prevClients)
                if (!cur[pid] && prevClients[pid].vis)
                    fxImplode(prevClients[pid]);
            for (var qid in prevClients)
                if (!cur[qid])
                    setChanged = true;
            if (moved.length > 0)
                fxMoves(moved, cur);
            fxResizeCheck(resized, setChanged);
        }
        for (var fid in cur)
            if (cur[fid].vis && cur[fid].foc)
                lastFocId = fid;
        for (var uid in cur) {
            var un = cur[uid];
            var ue = fxAlive("urgent", un.id);
            if (un.vis && un.urg) {
                if (!ue)
                    fxUrgent(un);
                else if (!sameRect(ue, un, 0))
                    fxRetarget(ue, un);   // the tile is being resized or moved
            } else if (ue && !ue.fake) {
                fxEnd(ue);
            }
        }
        for (var gid in prevClients)
            if (!cur[gid]) {
                var ge = fxAlive("urgent", prevClients[gid].id);
                if (ge)
                    fxEnd(ge);
            }
        var keptFx = [];   // a tile that went out of view (workspace switch): its effect ends at once
        for (var xi = 0; xi < fxList.length; xi++) {
            var xe = fxList[xi];
            if (xe.cid !== undefined && xe.kind !== "urgent" && (!cur[xe.cid] || !cur[xe.cid].vis))
                continue;
            keptFx.push(xe);
        }
        if (keptFx.length !== fxList.length) {
            fxList = keptFx;
            fxSeq++;
        }
        prevClients = cur;
        clientsInit = true;
    }

    function lutAt(frac) {
        var l = glowLut;
        if (l.length === 0)
            return "white";
        return l[Math.max(0, Math.min(l.length - 1, Math.floor(frac * l.length)))];
    }

    // Rounded rectangle path.
    function rrPath(ctx, x, y, w, h, r) {
        r = Math.max(0, Math.min(r, w / 2, h / 2));
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + w - r, y);
        ctx.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
        ctx.lineTo(x + w, y + h - r);
        ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
        ctx.lineTo(x + r, y + h);
        ctx.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
        ctx.lineTo(x, y + r);
        ctx.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5);
        ctx.closePath();
    }

    // Point on the rounded rectangle's outline, s px clockwise from the top edge's left end.
    function perimPoint(x, y, w, h, r, s) {
        var a = w - 2 * r, b = h - 2 * r, q = r * Math.PI / 2;
        var ang;
        if (s < a) return { x: x + r + s, y: y };
        s -= a;
        if (s < q) { ang = -Math.PI / 2 + s / r; return { x: x + w - r + r * Math.cos(ang), y: y + r + r * Math.sin(ang) }; }
        s -= q;
        if (s < b) return { x: x + w, y: y + r + s };
        s -= b;
        if (s < q) { ang = s / r; return { x: x + w - r + r * Math.cos(ang), y: y + h - r + r * Math.sin(ang) }; }
        s -= q;
        if (s < a) return { x: x + w - r - s, y: y + h };
        s -= a;
        if (s < q) { ang = Math.PI / 2 + s / r; return { x: x + r + r * Math.cos(ang), y: y + h - r + r * Math.sin(ang) }; }
        s -= q;
        if (s < b) return { x: x, y: y + h - r - s };
        s -= b;
        ang = Math.PI + s / r;
        return { x: x + r + r * Math.cos(ang), y: y + r + r * Math.sin(ang) };
    }

    function drawFx(ctx, e, now, scr) {
        var age = now - e.t;
        var f = age / e.dur;
        if (f < 0 || f >= 1)
            return;
        if (e.freeze) {   // preview only: hold the effect at its mid-point
            age = (e.kind === "mv2") ? 270 : 350;
            f = 0.5;
        }
        var ease = 1 - Math.pow(1 - f, 3);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (e.kind === "focus_runners") {   // old running-lights version, unused
            var rc = fxRect(e, now);
            var bx = rc.x - 2, by = rc.y - 2, bw = rc.w + 4, bh = rc.h + 4;
            var r = Math.max(1, Math.min(12, bw / 2 - 1, bh / 2 - 1));
            var a = bw - 2 * r;
            var P = 2 * a + 2 * (bh - 2 * r) + 2 * Math.PI * r;
            // the whole border flashes softly ...
            ctx.globalAlpha = (1 - f) * (1 - f) * 0.9;
            ctx.strokeStyle = lutAt(0);
            ctx.lineWidth = 4;
            rrPath(ctx, bx, by, bw, bh, r);
            ctx.stroke();
            // ... and two lights run from the top middle around to the bottom middle
            var head = P * 0.5 * ease;
            var L = P * 0.32;
            for (var d = -1; d <= 1; d += 2) {
                var prev = null;
                for (var k = 0; k <= 24; k++) {
                    var s = head - L * k / 24;
                    if (s < 0)
                        break;
                    var u = (a / 2 + d * s) % P;
                    if (u < 0)
                        u += P;
                    var pt = perimPoint(bx, by, bw, bh, r, u);
                    if (prev) {
                        var al = (1 - k / 24) * (1 - f * f * f);
                        ctx.strokeStyle = lutAt(0.8 * k / 24);
                        ctx.globalAlpha = al * 0.45;
                        ctx.lineWidth = 16;
                        ctx.beginPath();
                        ctx.moveTo(prev.x, prev.y);
                        ctx.lineTo(pt.x, pt.y);
                        ctx.stroke();
                        ctx.globalAlpha = al;
                        ctx.lineWidth = 4.5;
                        ctx.beginPath();
                        ctx.moveTo(prev.x, prev.y);
                        ctx.lineTo(pt.x, pt.y);
                        ctx.stroke();
                    }
                    prev = pt;
                }
            }
        } else if (e.kind === "spray") {
            for (var ip = 0; ip < e.parts.length; ip++) {
                var sq = e.parts[ip];
                var sa = age - sq.ts;
                if (sa < 0 || sa >= sq.life)
                    continue;
                var sf = sa / sq.life;
                ctx.globalAlpha = Math.min(1, (1 - sf) / 0.3);
                ctx.fillStyle = lutAt(sq.c * 0.6 + 0.4 * sf * sf * sf);
                ctx.beginPath();
                ctx.arc(sq.x + sq.vx * sa / 1000, sq.y + sq.vy * sa / 1000, sq.s * (1 - 0.5 * sf) + 0.3, 0, Math.PI * 2);
                ctx.fill();
            }
        } else if (e.kind === "implode") {
            var sc = Math.pow(1 - f, 5);   // fast start, soft landing
            var cxm = e.x + e.w / 2, cym = e.y + e.h / 2;
            ctx.globalAlpha = (1 - f) * 0.10;
            ctx.fillStyle = lutAt(0.3);
            rrPath(ctx, cxm - e.w * sc / 2, cym - e.h * sc / 2, e.w * sc, e.h * sc, 10 * sc + 2);
            ctx.fill();
            ctx.globalAlpha = (1 - f) * 0.8;
            ctx.strokeStyle = lutAt(f);
            ctx.lineWidth = 3 * (1 - f) + 0.8;
            rrPath(ctx, cxm - e.w * sc / 2, cym - e.h * sc / 2, e.w * sc, e.h * sc, 10 * sc + 2);
            ctx.stroke();
            if (f > 0.4) {
                var ff = (f - 0.4) / 0.6;
                var cg = ctx.createRadialGradient(cxm, cym, 0, cxm, cym, 20 + 60 * ff);
                cg.addColorStop(0, withAlpha(lutAt(0.2), 0.8 * (1 - ff)));
                cg.addColorStop(1, withAlpha(lutAt(0.2), 0));
                ctx.globalAlpha = 1;
                ctx.fillStyle = cg;
                ctx.fillRect(cxm - 90, cym - 90, 180, 180);
            }
        } else if (e.kind === "notify") {
            var nx = e.x, ny = e.y;
            var nr = 150 + 300 * ease;
            var ng = ctx.createRadialGradient(nx, ny, 0, nx, ny, nr);
            ng.addColorStop(0, withAlpha(lutAt(0.3), 0.85 * Math.pow(1 - f, 1.5)));
            ng.addColorStop(0.5, withAlpha(lutAt(0.3), 0.3 * (1 - f)));
            ng.addColorStop(1, withAlpha(lutAt(0.3), 0));
            ctx.globalAlpha = 1;
            ctx.fillStyle = ng;
            ctx.fillRect(nx, ny, nr, nr);
        } else if (e.kind === "level") {
            // volume (right edge) or brightness (left edge): a thin bar fills to the new level
            var envl = Math.min(1, age / 120) * Math.min(1, (e.dur - age) / 300);
            var uk = Math.min(1, (now - e.ut) / 160);
            var shown = e.pv + (e.val - e.pv) * (1 - Math.pow(1 - uk, 3));
            var LL = e.h * 0.4;
            var xl = (e.lk === "bri") ? e.x + 22 : e.x + e.w - 22;
            var yb = e.y + e.h / 2 + LL / 2;
            ctx.lineCap = "round";
            ctx.strokeStyle = "white";
            ctx.globalAlpha = envl * 0.2;
            ctx.lineWidth = 8;
            ctx.beginPath();
            ctx.moveTo(xl, yb);
            ctx.lineTo(xl, yb - LL);
            ctx.stroke();
            if (shown > 0.004) {
                var cl = e.muted ? lutAt(1) : lutAt(0.15 + 0.7 * Math.min(1, shown));
                var yt = yb - LL * Math.min(1, shown);
                ctx.strokeStyle = cl;
                ctx.globalAlpha = envl * 0.25;
                ctx.lineWidth = 20;
                ctx.beginPath();
                ctx.moveTo(xl, yb);
                ctx.lineTo(xl, yt);
                ctx.stroke();
                ctx.globalAlpha = envl * 0.95;
                ctx.lineWidth = 6;
                ctx.beginPath();
                ctx.moveTo(xl, yb);
                ctx.lineTo(xl, yt);
                ctx.stroke();
                ctx.fillStyle = cl;
                ctx.beginPath();
                ctx.arc(xl, yt, 5.5, 0, Math.PI * 2);
                ctx.fill();
            }
        } else if (e.kind === "sweep") {
            // fullscreen: a band of light crosses the tile (left to right when entering, back when leaving)
            var rs = fxRect(e, now);
            var bwid = Math.max(140, rs.w * 0.4);
            var spos = (e.dir > 0) ? (rs.x - bwid + (rs.w + 2 * bwid) * ease) : (rs.x + rs.w + bwid - (rs.w + 2 * bwid) * ease);
            ctx.save();
            rrPath(ctx, rs.x, rs.y, rs.w, rs.h, 10);
            ctx.clip();
            var sg = ctx.createLinearGradient(spos - bwid / 2, rs.y, spos + bwid / 2, rs.y + rs.h * 0.25);
            sg.addColorStop(0, withAlpha(lutAt(0.2), 0));
            sg.addColorStop(0.5, withAlpha(lutAt(0.2), 0.55 * (1 - f)));
            sg.addColorStop(1, withAlpha(lutAt(0.2), 0));
            ctx.globalAlpha = 1;
            ctx.fillStyle = sg;
            ctx.fillRect(rs.x, rs.y, rs.w, rs.h);
            ctx.restore();
            ctx.globalAlpha = (1 - f) * 0.6;
            ctx.strokeStyle = lutAt(0.2);
            ctx.lineWidth = 2;
            rrPath(ctx, rs.x, rs.y, rs.w, rs.h, 10);
            ctx.stroke();
        } else if (e.kind === "float") {
            // two rings leave the tile when it starts floating, and fall into it when it is tiled again
            var rf = fxRect(e, now);
            for (var kf = 0; kf < 2; kf++) {
                var ff = Math.max(0, Math.min(1, f * 1.25 - kf * 0.22));
                if (ff <= 0 || ff >= 1)
                    continue;
                var gf = 1 - Math.pow(1 - ff, 3);
                var gg = (e.dir > 0) ? 26 * gf : -18 * gf;
                ctx.globalAlpha = (1 - ff) * 0.75;
                ctx.strokeStyle = lutAt(0.65 + 0.3 * kf);
                ctx.lineWidth = 2.6 * (1 - ff) + 0.6;
                rrPath(ctx, rf.x - gg, rf.y - gg, rf.w + 2 * gg, rf.h + 2 * gg, 10 + gg * 0.3);
                ctx.stroke();
            }
        } else if (e.kind === "wash") {
            // workspace switch: a soft band of colour sweeps across the screen toward where the content goes
            var bww = e.w * 0.55;
            var wc = (e.dir > 0) ? e.x + e.w + bww * 0.3 - (e.w + bww * 0.6) * ease : e.x - bww * 0.3 + (e.w + bww * 0.6) * ease;
            ctx.save();
            ctx.beginPath();
            ctx.rect(e.x, e.y, e.w, e.h);
            ctx.clip();
            var wg = ctx.createLinearGradient(wc - bww / 2, 0, wc + bww / 2, 0);
            wg.addColorStop(0, withAlpha(lutAt(0.3), 0));
            wg.addColorStop(0.5, withAlpha(lutAt(0.3), 0.28 * (1 - f)));
            wg.addColorStop(1, withAlpha(lutAt(0.3), 0));
            ctx.globalAlpha = 1;
            ctx.fillStyle = wg;
            ctx.fillRect(e.x, e.y, e.w, e.h);
            ctx.restore();
        } else if (e.kind === "gaps") {
            // layout change: every gap between tiles lights up once
            var envg = Math.sin(Math.PI * f);
            for (var ig = 0; ig < e.lines.length; ig++) {
                var ln = e.lines[ig];
                ctx.strokeStyle = lutAt(0.5);
                var wgap = [16, 7, 2.2];
                var agap = [0.25, 0.4, 0.95];
                for (var kg = 0; kg < 3; kg++) {
                    ctx.globalAlpha = envg * agap[kg];
                    ctx.lineWidth = wgap[kg];
                    ctx.beginPath();
                    ctx.moveTo(ln.x1, ln.y1);
                    ctx.lineTo(ln.x2, ln.y2);
                    ctx.stroke();
                }
            }
        } else if (e.kind === "resize") {
            // the edges being dragged glow in the gap beside the tile
            var rz = fxRect(e, now);
            var envz = Math.min(1, age / 80) * Math.min(1, (e.dur - age) / 250);
            var zs = [];
            if (e.edges.l) zs.push([rz.x - 4, rz.y + 12, rz.x - 4, rz.y + rz.h - 12]);
            if (e.edges.r) zs.push([rz.x + rz.w + 4, rz.y + 12, rz.x + rz.w + 4, rz.y + rz.h - 12]);
            if (e.edges.t) zs.push([rz.x + 12, rz.y - 4, rz.x + rz.w - 12, rz.y - 4]);
            if (e.edges.b) zs.push([rz.x + 12, rz.y + rz.h + 4, rz.x + rz.w - 12, rz.y + rz.h + 4]);
            ctx.strokeStyle = lutAt(0.5);
            var wz = [14, 7, 2.2];
            var az = [0.25, 0.4, 0.95];
            for (var iz = 0; iz < zs.length; iz++)
                for (var kz = 0; kz < 3; kz++) {
                    ctx.globalAlpha = envz * az[kz];
                    ctx.lineWidth = wz[kz];
                    ctx.beginPath();
                    ctx.moveTo(zs[iz][0], zs[iz][1]);
                    ctx.lineTo(zs[iz][2], zs[iz][3]);
                    ctx.stroke();
                }
        } else if (e.kind === "keymode") {
            // screen edges tinted while the key mode lasts (blue for cursor mode, red for others)
            var envk = holdEnv(e, now);
            ctx.save();
            ctx.beginPath();
            ctx.rect(scr.x, scr.y, scr.w, scr.h);
            ctx.clip();
            ctx.strokeStyle = (e.mode === "cursor") ? lutAt(0) : lutAt(1);
            var wk = [90, 64, 42, 24, 10];
            for (var ik = 0; ik < wk.length; ik++) {
                ctx.globalAlpha = envk * 0.09;
                ctx.lineWidth = wk[ik];
                ctx.beginPath();
                ctx.rect(scr.x, scr.y, scr.w, scr.h);
                ctx.stroke();
            }
            ctx.restore();
        } else if (e.kind === "plug") {
            // two lights start in the bottom-left corner and run around the screen edge to the top-right
            var rr = 10;
            var qx = scr.x + 3, qy = scr.y + 3, qw = scr.w - 6, qh = scr.h - 6;
            var pa = qw - 2 * rr, pb = qh - 2 * rr, pq = rr * Math.PI / 2;
            var PP = 2 * pa + 2 * pb + 4 * pq;
            var u0 = 2 * pa + pb + 2.5 * pq;   // the bottom-left corner
            var pe = 1 - Math.pow(1 - f, 2);
            var ph = PP / 2 * pe;
            var PL = PP * 0.3;
            if (f < 0.3) {   // a glow in the corner where it starts
                var cg = ctx.createRadialGradient(scr.x, scr.y + scr.h, 0, scr.x, scr.y + scr.h, 340);
                var cc = lutAt(0).replace("rgb(", "rgba(");
                cg.addColorStop(0, cc.replace(")", ",1)"));
                cg.addColorStop(1, cc.replace(")", ",0)"));
                ctx.globalAlpha = 1 - f / 0.3;
                ctx.fillStyle = cg;
                ctx.fillRect(scr.x, scr.y + scr.h - 340, 340, 340);
            }
            for (var pd = -1; pd <= 1; pd += 2) {
                var pprev = null;
                for (var pk = 0; pk <= 60; pk++) {
                    var ps = ph - PL * pk / 60;
                    if (ps < 0)
                        break;
                    var pu = (u0 + pd * ps) % PP;
                    if (pu < 0)
                        pu += PP;
                    var ppt = perimPoint(qx, qy, qw, qh, rr, pu);
                    if (pprev) {
                        var pal = (1 - pk / 60) * (1 - f * f * f);
                        ctx.strokeStyle = lutAt(0.8 * pk / 60 + 0.1 * f);
                        ctx.lineCap = "butt";
                        ctx.globalAlpha = Math.min(1, pal * 0.8);
                        ctx.lineWidth = 46;
                        ctx.beginPath();
                        ctx.moveTo(pprev.x, pprev.y);
                        ctx.lineTo(ppt.x, ppt.y);
                        ctx.stroke();
                        ctx.lineCap = "round";
                        ctx.globalAlpha = pal;
                        ctx.lineWidth = 10;
                        ctx.beginPath();
                        ctx.moveTo(pprev.x, pprev.y);
                        ctx.lineTo(ppt.x, ppt.y);
                        ctx.stroke();
                    }
                    pprev = ppt;
                }
            }
        } else if (e.kind === "urgent") {
            // an urgent tile breathes a soft red edge until it is focused
            var ru = fxRect(e, now);
            var envu = holdEnv(e, now) * (0.35 + 0.65 * (0.5 + 0.5 * Math.sin(now * 0.004)));
            ctx.save();
            rrPath(ctx, ru.x, ru.y, ru.w, ru.h, 10);
            ctx.clip();
            ctx.strokeStyle = lutAt(1);
            var wu = [40, 28, 18, 10, 5];
            for (var iu = 0; iu < wu.length; iu++) {
                ctx.globalAlpha = envu * 0.12;
                ctx.lineWidth = wu[iu];
                rrPath(ctx, ru.x, ru.y, ru.w, ru.h, 10);
                ctx.stroke();
            }
            ctx.restore();
            ctx.globalAlpha = envu * 0.85;
            ctx.lineWidth = 2;
            rrPath(ctx, ru.x, ru.y, ru.w, ru.h, 10);
            ctx.stroke();
        } else if (e.kind === "hop") {
            // a glowing dot flies along a curve from the old focused tile to the new one, with a tail
            var hx = (e.ax + e.bx) / 2, hy = (e.ay + e.by) / 2;
            var hdx = e.bx - e.ax, hdy = e.by - e.ay;
            var cx1 = hx - hdy * 0.25, cy1 = hy + hdx * 0.25;   // control point: bends the path
            var th = 1 - Math.pow(1 - f, 3);
            var hprev = null;
            for (var hk = 0; hk <= 40; hk++) {
                var tt = th - 0.4 * hk / 40;
                if (tt < 0)
                    break;
                var u1 = 1 - tt;
                var hpt = { x: u1 * u1 * e.ax + 2 * u1 * tt * cx1 + tt * tt * e.bx,
                            y: u1 * u1 * e.ay + 2 * u1 * tt * cy1 + tt * tt * e.by };
                if (hprev) {
                    var hal = (1 - hk / 40) * Math.min(1, (1 - f) / 0.3);
                    ctx.strokeStyle = lutAt(0.8 * hk / 40);
                    ctx.lineCap = "butt";
                    ctx.globalAlpha = hal * 0.3;
                    ctx.lineWidth = 14 * (1 - hk / 40) + 2;
                    ctx.beginPath();
                    ctx.moveTo(hprev.x, hprev.y);
                    ctx.lineTo(hpt.x, hpt.y);
                    ctx.stroke();
                    ctx.lineCap = "round";
                    ctx.globalAlpha = hal;
                    ctx.lineWidth = 4 * (1 - hk / 40) + 0.8;
                    ctx.beginPath();
                    ctx.moveTo(hprev.x, hprev.y);
                    ctx.lineTo(hpt.x, hpt.y);
                    ctx.stroke();
                } else {
                    ctx.globalAlpha = Math.min(1, (1 - f) / 0.3);
                    ctx.fillStyle = lutAt(0);
                    ctx.beginPath();
                    ctx.arc(hpt.x, hpt.y, 5, 0, Math.PI * 2);
                    ctx.fill();
                }
                hprev = hpt;
            }
        } else if (e.kind === "mv1") {
            // 1: lit while moving: the tile's edges glow while it travels, then dim
            var r1 = fxRect(e, now);
            var env1 = Math.sin(Math.PI * f);
            var gr1 = ctx.createLinearGradient(r1.x, r1.y, r1.x + r1.w, r1.y + r1.h);
            gr1.addColorStop(0, lutAt(0));
            gr1.addColorStop(0.5, lutAt(0.5));
            gr1.addColorStop(1, lutAt(1));
            ctx.save();
            rrPath(ctx, r1.x, r1.y, r1.w, r1.h, 10);
            ctx.clip();
            ctx.strokeStyle = gr1;
            var w1 = [44, 32, 22, 14, 8];
            for (var i1 = 0; i1 < w1.length; i1++) {
                ctx.globalAlpha = env1 * 0.13;
                ctx.lineWidth = w1[i1];
                rrPath(ctx, r1.x, r1.y, r1.w, r1.h, 10);
                ctx.stroke();
            }
            ctx.restore();
            ctx.globalAlpha = env1 * 0.9;
            ctx.lineWidth = 2;
            rrPath(ctx, r1.x, r1.y, r1.w, r1.h, 10);
            ctx.stroke();
        } else if (e.kind === "mv2") {
            // 2: landing flash: one short bright flash of the rim starting 100 ms after the move begins
            var r2 = fxRect(e, now);
            var env2 = Math.max(0, 1 - Math.abs(age - 270) / 170);
            if (env2 > 0) {
                var gr2 = ctx.createLinearGradient(r2.x, r2.y, r2.x + r2.w, r2.y + r2.h);
                gr2.addColorStop(0, lutAt(0));
                gr2.addColorStop(1, lutAt(1));
                ctx.strokeStyle = gr2;
                ctx.globalAlpha = env2 * 0.3;
                ctx.lineWidth = 14;
                rrPath(ctx, r2.x, r2.y, r2.w, r2.h, 10);
                ctx.stroke();
                ctx.globalAlpha = env2;
                ctx.lineWidth = 3;
                rrPath(ctx, r2.x, r2.y, r2.w, r2.h, 10);
                ctx.stroke();
            }
        } else if (e.kind === "mv3") {
            // 3: swap link: a glowing line joins the centers of the two tiles while they trade places
            var ra = fxRect(e, now);
            var rb = fxRect(e.eb, now);
            var ax = ra.x + ra.w / 2, ay = ra.y + ra.h / 2;
            var bx3 = rb.x + rb.w / 2, by3 = rb.y + rb.h / 2;
            var env3 = Math.sin(Math.PI * f);
            var gr3 = ctx.createLinearGradient(ax, ay, bx3, by3);
            gr3.addColorStop(0, lutAt(0));
            gr3.addColorStop(0.5, lutAt(0.5));
            gr3.addColorStop(1, lutAt(1));
            ctx.strokeStyle = gr3;
            ctx.globalAlpha = env3 * 0.25;
            ctx.lineWidth = 12;
            ctx.beginPath();
            ctx.moveTo(ax, ay);
            ctx.lineTo(bx3, by3);
            ctx.stroke();
            ctx.globalAlpha = env3 * 0.95;
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(ax, ay);
            ctx.lineTo(bx3, by3);
            ctx.stroke();
            ctx.globalAlpha = env3;
            ctx.fillStyle = lutAt(0);
            ctx.beginPath();
            ctx.arc(ax, ay, 5, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = lutAt(1);
            ctx.beginPath();
            ctx.arc(bx3, by3, 5, 0, Math.PI * 2);
            ctx.fill();
        } else if (e.kind === "mv4") {
            // 4: gap shimmer: only the gap between the two swapped tiles lights up
            var gl = e.gap;
            var env4 = Math.sin(Math.PI * f);
            var gr4 = ctx.createLinearGradient(gl.x1, gl.y1, gl.x2, gl.y2);
            gr4.addColorStop(0, lutAt(0));
            gr4.addColorStop(0.5, lutAt(0.5));
            gr4.addColorStop(1, lutAt(1));
            ctx.strokeStyle = gr4;
            ctx.globalAlpha = env4 * 0.22;
            ctx.lineWidth = 16;
            ctx.beginPath();
            ctx.moveTo(gl.x1, gl.y1);
            ctx.lineTo(gl.x2, gl.y2);
            ctx.stroke();
            ctx.globalAlpha = env4 * 0.9;
            ctx.lineWidth = 4;
            ctx.beginPath();
            ctx.moveTo(gl.x1, gl.y1);
            ctx.lineTo(gl.x2, gl.y2);
            ctx.stroke();
        } else if (e.kind === "mv5") {
            // 5: squash rim: a thin outline overshoots the tile a little, then eases back
            var r5 = fxRect(e, now);
            var g5 = 12 * (1 - f) * Math.sin(f * Math.PI * 2.2);
            var gr5 = ctx.createLinearGradient(r5.x, r5.y, r5.x + r5.w, r5.y + r5.h);
            gr5.addColorStop(0, lutAt(0));
            gr5.addColorStop(1, lutAt(1));
            ctx.strokeStyle = gr5;
            ctx.globalAlpha = (1 - f) * 0.22;
            ctx.lineWidth = 9;
            rrPath(ctx, r5.x - g5, r5.y - g5, r5.w + 2 * g5, r5.h + 2 * g5, 10 + g5 * 0.3);
            ctx.stroke();
            ctx.globalAlpha = (1 - f) * 0.95;
            ctx.lineWidth = 2.5;
            rrPath(ctx, r5.x - g5, r5.y - g5, r5.w + 2 * g5, r5.h + 2 * g5, 10 + g5 * 0.3);
            ctx.stroke();
        } else if (e.kind === "focus") {
            // The tile lights up from its edges inward (stays glued to the tile), then settles.
            var rc2 = fxRect(e, now);
            var env = f < 0.15 ? f / 0.15 : Math.pow(1 - (f - 0.15) / 0.85, 2);
            var grad = ctx.createLinearGradient(rc2.x, rc2.y, rc2.x + rc2.w, rc2.y + rc2.h);
            grad.addColorStop(0, lutAt(0));
            grad.addColorStop(0.5, lutAt(0.5));
            grad.addColorStop(1, lutAt(1));
            ctx.save();
            rrPath(ctx, rc2.x, rc2.y, rc2.w, rc2.h, 10);
            ctx.clip();
            ctx.strokeStyle = grad;
            var widths = [44, 32, 22, 14, 8];   // only the inner half of each stroke shows: a soft falloff
            for (var wi = 0; wi < widths.length; wi++) {
                ctx.globalAlpha = env * 0.13;
                ctx.lineWidth = widths[wi];
                rrPath(ctx, rc2.x, rc2.y, rc2.w, rc2.h, 10);
                ctx.stroke();
            }
            ctx.restore();
            ctx.strokeStyle = grad;
            ctx.globalAlpha = env * 0.9;
            ctx.lineWidth = 2;
            rrPath(ctx, rc2.x, rc2.y, rc2.w, rc2.h, 10);
            ctx.stroke();
        } else if (e.kind === "open" || e.kind === "close") {
            var rc = fxRect(e, now);
            var g = (e.kind === "close") ? -24 * ease : 30 * ease;   // outline flies out, or shrinks in
            ctx.globalAlpha = (1 - f) * 0.8;
            ctx.strokeStyle = lutAt(f);
            ctx.lineWidth = 3 * (1 - f) + 0.6;
            rrPath(ctx, rc.x - g, rc.y - g, rc.w + 2 * g, rc.h + 2 * g, 10 + g * 0.3);
            ctx.stroke();
            for (var m = 0; e.parts && m < e.parts.length; m++) {
                var q = e.parts[m];
                var pf = age / q.life;
                if (pf >= 1)
                    continue;
                ctx.globalAlpha = Math.min(1, (1 - pf) / 0.3);
                var ci = q.cf * 0.6 + (1 - q.cf * 0.6) * pf * pf * pf;
                ctx.fillStyle = lutAt(ci);
                ctx.beginPath();
                ctx.arc(q.x + q.vx * age / 1000, q.y + q.vy * age / 1000, q.s * (1 - 0.5 * pf), 0, Math.PI * 2);
                ctx.fill();
            }
        } else if (e.kind === "ghost") {
            // faint copies of the tile's outline trail behind it while it moves
            for (var i = 0; i < 16; i++) {
                var fi = Math.max(0, ease - i * 0.028);
                var gx = e.fx + (e.x - e.fx) * fi;
                var gy = e.fy + (e.y - e.fy) * fi;
                var gw = e.fw + (e.w - e.fw) * fi;
                var gh = e.fh + (e.h - e.fh) * fi;
                rrPath(ctx, gx, gy, gw, gh, 10);
                ctx.fillStyle = lutAt(i / 16);
                ctx.globalAlpha = (1 - f) * 0.018 * (1 - i / 16);
                ctx.fill();
                ctx.strokeStyle = lutAt(i / 16);
                ctx.globalAlpha = (1 - f) * 0.16 * (1 - i / 16);
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
        }
        ctx.globalAlpha = 1;
    }

    // One drawing layer. Strokes are fully opaque (no joint beads); the see-through look
    // comes from the whole layer's opacity. Fade = the tail thinning to a sharp point.
    component Layer: Canvas {
        property var owner
        property bool isCore: false
        property bool ghost: false   // faint long-lived afterimage of the trail only
        property bool pet: false     // the desktop pet: same comet, but it does not react to scrolling
        property real sz: 1          // size factor (the pet is smaller)
        property var lutOver: null   // own color ramp (the pet)
        property var wbx: []         // scratch: tail point positions (reused every frame)
        property var wby: []
        property var spk: []         // scratch: solid sparkles by color index (flat x, y, r triples)
        property bool small: false   // uses the owner's smaller glow/core box (cbox*); the pet has none
        renderTarget: Canvas.Image
        x: small ? owner.cboxX : owner.boxX
        y: small ? owner.cboxY : owner.boxY
        width: small ? owner.cboxW : owner.boxW
        height: small ? owner.cboxH : owner.boxH
        // the afterimage is invisible while its switch is off: do not paint it, and repaint when it comes back
        onOpacityChanged: if (ghost && opacity > 0) requestPaint()

        // The pet as a firefly swarm: root.swarmCount small lights that act as one animal. Each light chases its own
        // orbit around the pet's real position (a spring), so the swarm bunches up at rest, trails behind
        // when fast and bursts apart when the pet flees. The glow canvas draws soft halos, the core canvas
        // draws the bright dots. The state lives in the PetView (flies, fliesT, scat) and is stepped here.
        // Moves the lights one step. Light 0 has a small, slow orbit, so it stays close to the middle.
        function stepSwarm(now) {
            var hx = owner.hx, hy = owner.hy;
            var fl = owner.flies;
            if (fl.length === 0) {
                for (var i = 0; i < root.swarmCount; i++)
                    fl.push({ x: hx, y: hy, vx: 0, vy: 0, ph: Math.random() * 6.28,
                              w: i === 0 ? 1.3 : 1.2 + Math.random() * 1.4, r: i === 0 ? 0.5 : 0.6 + Math.random() * 0.6 });
                owner.fliesT = now;
            }
            var dt = Math.min(0.05, Math.max(0, (now - owner.fliesT) / 1000));
            if (dt <= 0)
                return;   // the glow and the core canvas paint in the same millisecond: step once
            owner.fliesT = now;
            var fleeing = root.petMode === "flee" ? 1 : 0;
            owner.scat += (fleeing - owner.scat) * Math.min(1, dt * (fleeing ? 14 : 3));
            var spd = Math.hypot(root.petVx, root.petVy);
            var rest = 12 + owner.scat * 80 + Math.min(40, spd * 0.04);
            var t = now / 1000;
            // Trick shapes: while the pet draws one (its trail life is stretched), the lights spread out along
            // the pet's recent path: light 0 at the head, the last light at 85% of the path's age. Together
            // they trace the shape. When the trick ends the shape blends back into the normal swarm.
            // The shape is "drawn" while the pet is in a trick and moving. At the end of a trick the pet creeps for a
            // while: the moment it slows down after being fast, the shape is over and the swarm explodes (no crawling).
            var inTrick = root.petMode === "trick" && root.petTrickGo;
            if (!inTrick) {
                owner.fast = false;
                owner.cut = false;
            } else if (!owner.cut) {
                if (root.petTrickKind === "pendulum") {
                    // it slows to a stop at every turn of the swing, so speed says nothing here: end when the swing is small
                    if (Date.now() - root.petTrickT0 > root.petTrickDur * 0.75)
                        owner.cut = true;
                } else if (root.petV > 0.2) {
                    owner.fast = true;
                } else if (owner.fast && root.petV < 0.12 && Date.now() - root.petTrickT0 > 600) {
                    owner.cut = true;
                }
            }
            var drawing = inTrick && !owner.cut;
            owner.shape += ((drawing && root.petTrickKind !== "dvd" ? 1 : 0) - owner.shape) * Math.min(1, dt * (drawing ? 6 : 12));
            if ((owner.wasDrawing && !drawing) || root.petBurstAt > owner.burstSeen) {
                owner.burstSeen = root.petBurstAt;
                // The trick just ended: no pulling together. The lights fly outward from the middle of the shape
                // (the springs are soft for a moment, so nothing snaps back), each gets a new random orbit, and
                // the springs stiffen again while the swarm is still wide, so it settles into orbiting, not piling up.
                var mx = 0, my = 0;
                for (var c0 = 0; c0 < fl.length; c0++) {
                    mx += fl[c0].x / fl.length;
                    my += fl[c0].y / fl.length;
                }
                for (var b = 0; b < fl.length; b++) {
                    var bf = fl[b];
                    var bx = bf.x - mx, by = bf.y - my;
                    var bd = Math.hypot(bx, by);
                    if (bd < 6) {
                        var ba = Math.random() * Math.PI * 2;
                        bx = Math.cos(ba);
                        by = Math.sin(ba);
                        bd = 1;
                    }
                    var bs = 320 + Math.random() * 220;
                    bf.vx += bx / bd * bs;
                    bf.vy += by / bd * bs;
                    bf.ph = Math.random() * 6.28;
                    bf.w = b === 0 ? 1.3 : 1.2 + Math.random() * 1.4;
                }
                owner.shape = 0;
                owner.boom = 1;
                owner.scat = Math.max(owner.scat, 0.55);
            }
            owner.boom = Math.max(0, owner.boom - dt / 0.6);
            owner.wasDrawing = drawing;
            var daring = root.petMode === "dare";
            var annoyed = !daring && root.petAnnoy > 600;
            var tricking = root.petMode === "trick";
            if (daring)
                owner.moodKind = "blue";
            else if (annoyed)
                owner.moodKind = "red";
            else if (tricking)
                owner.moodKind = "green";
            owner.moodA += ((daring || annoyed || tricking ? 1 : 0) - owner.moodA) * Math.min(1, dt * 8);
            var pp = owner.pts;
            var nf = fl.length;
            for (var j = 0; j < nf; j++) {
                var f = fl[j];
                var ox = Math.cos(f.ph + t * f.w) * rest * f.r - root.petVx * 0.03 * (0.5 + j * 0.12);
                var oy = Math.sin(f.ph + t * f.w * 1.1) * rest * f.r - root.petVy * 0.03 * (0.5 + j * 0.12);
                var gx = hx + ox, gy = hy + oy;
                if (owner.shape > 0.01 && root.petTrickKind === "pendulum") {
                    // the lights hang on the rope of the pendulum, evenly from the pivot to the bob (light 0)
                    var pvx = root.petTrickCX - owner.host.modelData.x, pvy = root.petTrickCY - owner.host.modelData.y;
                    var rf = 1 - j / nf;
                    gx += (pvx + (hx - pvx) * rf - gx) * owner.shape;
                    gy += (pvy + (hy - pvy) * rf - gy) * owner.shape;
                } else if (owner.shape > 0.01 && pp.length > 1) {
                    var span = root.petLife * 0.85;
                    if (root.petTrickCycle > 0)
                        span = Math.min(span, root.petTrickCycle * (nf - 1) / nf);   // the lights share one round of the shape
                    var want = now - (j / (nf - 1)) * span;
                    var q = pp.length - 1;
                    while (q > 0 && pp[q].t > want)
                        q--;
                    gx += (pp[q].x - gx) * owner.shape;
                    gy += (pp[q].y - gy) * owner.shape;
                }
                var kk = 60 + 90 * owner.shape, cc = 8 + 8 * owner.shape;
                if (root.petMode === "trick" && root.petTrickKind === "dvd") {   // rigid: the lights follow the bounce with no lag
                    kk = 320;
                    cc = 32;
                }
                kk += (12 - kk) * owner.boom;   // right after a trick: soft springs, so the burst can fly out
                cc += (4 - cc) * owner.boom;
                f.vx += ((gx - f.x) * kk - f.vx * cc) * dt;
                f.vy += ((gy - f.y) * kk - f.vy * cc) * dt;
                f.x += f.vx * dt;
                f.y += f.vy * dt;
            }
        }

        function paintSwarm(ctx, now, lut, core) {
            root.drawLights(ctx, owner.flies, lut[0], owner.moodKind, owner.moodA, root.petMixTint, root.petMixA, core, now, 0, 0, 1);
        }

        // One tapered tail through the points p (newest last): wobble at the tip, thicker when fast, sharp point.
        function drawTrail(ctx, p, last, now, life, lut, k, n) {
            // Tail wobble: only the last 50% of the tail sways, most at the tip.
            if (last < 1)
                return;
            // Points older than `life` draw nothing: start at the first live one (p is not strictly
            // time-sorted, so the check below stays per point). Positions are copied into reusable
            // arrays, so no objects are allocated per frame.
            var f0 = 0;
            while (f0 <= last && now - p[f0].t >= life)
                f0++;
            var i0 = Math.max(1, f0);
            if (i0 > last)
                return;
            var wob = root.wobble > 0 && root.fxOn("wobble") && last > 1 && !ghost && !(pet && root.petLife > 700);   // the afterimage stays straight
            var wobAmp = root.wobble * sz;
            var xs = wbx, ys = wby;
            for (var w = i0 - 1; w <= last; w++) {
                var pw = p[w];
                if (wob) {
                    var pa = p[w > 0 ? w - 1 : 0];
                    var pb = p[w < last ? w + 1 : last];
                    var tx = pb.x - pa.x;
                    var ty = pb.y - pa.y;
                    var tl = Math.sqrt(tx * tx + ty * ty) || 1;
                    var wf = Math.max(0, Math.min(1, (now - pw.t) / life) - 0.5) / 0.5;   // only the last 50% of the tail
                    var off = Math.sin(now * 0.011 + pw.id * 0.7) * wobAmp * wf;
                    xs[w] = pw.x - ty / tl * off;
                    ys[w] = pw.y + tx / tl * off;
                } else {
                    xs[w] = pw.x;
                    ys[w] = pw.y;
                }
            }
            var mw = root.maxWidth * k;
            var dw = root.fxOn("drag") ? root.dragWidth : 1;
            var lastCi = -1;   // the color is set only when it changes (a string parse each time)
            for (var i = i0; i <= last; i++) {
                var pi = p[i];
                var a = 1 - (now - pi.t) / life;
                if (a <= 0)
                    continue;
                // Speed: slow = thin, fast = thick.
                var sc = 0.55 + 0.9 * Math.min(1, pi.v / 2.5);
                var lw = mw * sc * a * (pi.d ? dw : 1);   // -> 0 at the tip: sharp point
                if (lw < 0.08)
                    continue;   // thinner than 0.08 px is not visible
                // Smooth curve: run through midpoints, points are the bend controls.
                var cx1 = xs[i], cy1 = ys[i];
                var sx = (i === 1) ? xs[0] : (xs[i - 1] + cx1) / 2;
                var sy = (i === 1) ? ys[0] : (ys[i - 1] + cy1) / 2;
                var ex = (i === last) ? cx1 : (cx1 + xs[i + 1]) / 2;
                var ey = (i === last) ? cy1 : (cy1 + ys[i + 1]) / 2;
                var ci = Math.min(n - 1, Math.floor((1 - a) * n));
                if (ci !== lastCi) {
                    ctx.strokeStyle = lut[ci];
                    lastCi = ci;
                }
                ctx.beginPath();
                ctx.moveTo(sx, sy);
                ctx.quadraticCurveTo(cx1, cy1, ex, ey);
                ctx.lineWidth = lw;
                ctx.stroke();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.setTransform(1, 0, 0, 1, 0, 0);
            if (ghost && opacity === 0)
                return;
            ctx.clearRect(0, 0, width, height);
            var p = owner.pts;
            var bz = pet && !isCore && owner.bursting === true;   // while sparks fly only the core canvas draws
            var q = bz ? [] : owner.parts;
            var rp = bz ? [] : owner.rips;
            var last = p.length - 1;
            var lut = lutOver ? lutOver : (isCore ? root.coreLut : root.glowLut);
            var n = lut.length;
            var ext = [];   // touchscreen fingers: drawn on the ghost layer only (the long faint trail)
            if (ghost && owner.ext) {
                for (var xi = 0; xi < owner.ext.length; xi++)
                    if (owner.ext[xi] && owner.ext[xi].pts.length > 0)
                        ext.push(owner.ext[xi]);
            }
            if (n === 0 || (last < 0 && q.length === 0 && rp.length === 0 && !owner.hasHead && ext.length === 0))
                return;
            ctx.setTransform(1, 0, 0, 1, -x, -y);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            var now = Date.now();
            var k = (ghost ? 0.6 : (isCore ? 0.33 : 1)) * sz;
            var life = ghost ? root.ghostMs : (pet ? root.petLife : root.lifeMs);
            var swarm = pet && !ghost && root.fxOn("swarm");   // the pet is drawn as a firefly swarm, not as a small comet
            if (swarm) {
                if (owner.hasHead)
                    stepSwarm(now);   // the swarm has no tails; it is drawn below
            } else {
                drawTrail(ctx, p, last, now, life, lut, k, n);
                for (var ei = 0; ei < ext.length; ei++)
                    drawTrail(ctx, ext[ei].pts, ext[ei].pts.length - 1, now, root.touchGhostMs, lut, k, n);
            }

            if (ghost) {
                ctx.globalAlpha = 1;
                return;
            }

            // Comet head: always drawn on the cursor (the real cursor is hidden).
            // 2 px radius at rest (6 px for the soft halo); grows with speed while moving.
            if (swarm && owner.hasHead)
                paintSwarm(ctx, now, lut, isCore);
            var heads = [];   // the cursor head (touch fingers have no head, only the ghost trail)
            if (owner.hasHead && !swarm)
                heads.push({ p: p, last: last, x: owner.hx, y: owner.hy });
            for (var hi = 0; hi < heads.length; hi++) {
                var hp = heads[hi].p;
                var hl = heads[hi].last;
                var rest = (isCore ? 2 : 6) * sz;
                var r = rest;
                var stretch = 1;   // head is stretched along the direction of travel
                var hang = 0;
                if (hl >= 0) {
                    var al = 1 - (now - hp[hl].t) / root.lifeMs;
                    if (al > 0) {
                        var sp = Math.min(1, hp[hl].v / 2.5);
                        r = Math.max(rest, (isCore ? 3 + 2 * sp : 8 + 5 * sp) * al * sz);
                        if (hl >= 1) {
                            stretch = root.fxOn("stretch") ? 1 + 1.1 * sp * al : 1;
                            hang = Math.atan2(hp[hl].y - hp[hl - 1].y, hp[hl].x - hp[hl - 1].x);
                        }
                    }
                }
                ctx.fillStyle = lut[0];
                // Scrolling: the head stretches into an oval along the scroll direction, then relaxes.
                var sf = (!pet && hi === 0 && root.fxOn("scroll")) ? Math.max(0, 1 - (now - root.scrollT) / 350) : 0;
                if (sf > 0) {
                    var ss = 1 + 0.8 * sf;
                    if (ss > stretch) {
                        stretch = ss;
                        hang = root.scrollAng;
                    }
                    r = Math.max(r, rest * (1 + 0.15 * sf));
                }
                ctx.save();
                ctx.translate(heads[hi].x, heads[hi].y);
                ctx.rotate(hang);
                ctx.scale(stretch, 1 / Math.sqrt(stretch));   // keeps the area about the same
                ctx.beginPath();
                ctx.arc(0, 0, r, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
            }

            // Sparkles shed from the tail end: drift, twinkle, shrink, fade.
            // Solid ones (first 92% of life) are batched: one path and one fill per color.
            var gl = pet ? lut : root.glowLut;
            var gn = gl.length;
            var sk = spk;
            var skUsed = false;
            var sMul = isCore ? 1 : 3.5;
            for (var m = 0; m < q.length; m++) {
                var s = q[m];
                var age = now - s.t;
                var f = age / s.life;
                if (f >= 1)
                    continue;
                // each sparkle starts at a random spot of the bar gradient and drifts to the tail color (red) as it dies
                var ci = s.cf * 0.6 + (1 - s.cf * 0.6) * f * f * f * f;
                var cidx = Math.min(gn - 1, Math.floor(ci * gn));
                var px = s.x + s.vx * age / 1000;
                var py = s.y + s.vy * age / 1000;
                var sr = s.s * (1 - 0.5 * f) * sMul;
                if (f <= 0.92) {
                    var bk = sk[cidx];
                    if (bk === undefined || bk === null) {
                        bk = [];
                        sk[cidx] = bk;
                    }
                    bk.push(px, py, sr);
                    skUsed = true;
                } else {   // smooth fade (no twinkle)
                    ctx.globalAlpha = (1 - f) / 0.08;
                    ctx.fillStyle = gl[cidx];
                    ctx.beginPath();
                    ctx.arc(px, py, sr, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
            if (skUsed) {
                ctx.globalAlpha = 1;
                for (var bi = 0; bi < sk.length; bi++) {
                    var bq = sk[bi];
                    if (bq === undefined || bq === null || bq.length === 0)
                        continue;
                    ctx.fillStyle = gl[bi];
                    for (var bj = 0; bj < bq.length; bj += 3) {
                        var er = bq[bj + 2];
                        ctx.beginPath();
                        ctx.ellipse(bq[bj] - er, bq[bj + 1] - er, er * 2, er * 2);
                        ctx.fill();
                    }
                    bq.length = 0;
                }
            }
            // Rings (click, release pop) and edge glows. Each has its own duration and size.
            for (var u = 0; u < rp.length; u++) {
                var R = rp[u];
                var rf = (now - R.t) / R.dur;
                if (rf <= 0 || rf >= 1)
                    continue;
                if (R.edge) {   // soft glow where the cursor touched the screen edge
                    if (isCore)
                        continue;
                    var c0 = lut[0].replace("rgb(", "rgba(");
                    var gr = ctx.createRadialGradient(R.x, R.y, 0, R.x, R.y, 70);
                    gr.addColorStop(0, c0.replace(")", ",1)"));
                    gr.addColorStop(1, c0.replace(")", ",0)"));
                    ctx.globalAlpha = 1 - rf;
                    ctx.fillStyle = gr;
                    ctx.fillRect(R.x - 70, R.y - 70, 140, 140);
                    continue;
                }
                var ease = 1 - Math.pow(1 - rf, 3);
                ctx.globalAlpha = (1 - rf) * (R.a === undefined ? 1 : R.a);
                ctx.strokeStyle = lut[Math.min(n - 1, Math.floor(rf * n))];
                ctx.lineWidth = ((isCore ? 2.2 : 6) * (1 - rf) + 0.4) * R.sz;
                ctx.beginPath();
                var rr0 = (6 + 44 * ease) * R.sz;
                if (R.shape === "square") {   // right click: a square ring
                    ctx.rect(R.x - rr0, R.y - rr0, rr0 * 2, rr0 * 2);
                } else if (R.shape === "tri") {   // middle click: a triangle ring
                    var tr = rr0 * 1.25;
                    for (var tv = 0; tv < 3; tv++) {
                        var ta = -Math.PI / 2 + tv * Math.PI * 2 / 3;
                        if (tv === 0)
                            ctx.moveTo(R.x + Math.cos(ta) * tr, R.y + Math.sin(ta) * tr);
                        else
                            ctx.lineTo(R.x + Math.cos(ta) * tr, R.y + Math.sin(ta) * tr);
                    }
                    ctx.closePath();
                } else {
                    ctx.arc(R.x, R.y, rr0, 0, Math.PI * 2);
                }
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
        }
    }

    // The desktop pet on one screen. behindLayer false = drawn on the top layer (in front of the windows),
    // true = drawn on the bottom layer (the windows cover it). Only the one matching root.petBehind draws.
    component PetView: Item {
            id: petI
            required property var host
            property bool behindLayer: false
            opacity: root.petFade * root.petDim
            anchors.fill: parent

            property var pts: []
            property var parts: []   // always empty: the Layer code expects these
            property var rips: []    // pet ripples {x, y, t, dur, sz}
            property int boxX: 0
            property int boxY: 0
            property int boxW: 1
            property int boxH: 1
            property bool hasHead: false
            property bool drawn: false   // something is on the canvas that must still be erased
            property real hx: 0
            property real hy: 0
            property var flies: []        // swarm look: the lights {x, y, vx, vy, ph, w, r}
            property real shape: 0        // 0..1 how much the lights follow a trick shape (the pet's recent path)
            property bool wasDrawing: false   // a trick shape was being drawn at the last step (to catch its end)
            property double burstSeen: root.petBurstAt      // the last merge burst (root.petBurstAt) this view has already played
            property string moodKind: "red"   // colour: red = annoyed by the cursor, blue = daring it, green = doing a trick
            property real moodA: 0            // 0..1 how much of a mood is on (fades in and out)
            property bool fast: false        // the pet has been moving fast during this trick
            property bool cut: false          // the pet slowed down at the end of the trick: the shape is over
            property real boom: 0             // 1 right after a trick ends, falls to 0 in 0.6 s: how soft the springs are
            property double fliesT: 0     // when they were last stepped
            property real scat: 0         // 0..1 how far the swarm is scattered (fleeing)

            property bool bursting: false
            property real bcx: 0   // where the pet burst (box centre while sparks fly)
            property real bcy: 0

            function updateBox() {
                if (parts.length > 0) {
                    boxW = 520;
                    boxH = 520;
                    boxX = Math.round(bcx - 260);
                    boxY = Math.round(bcy - 260);
                    return;
                }
                var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
                for (var i = 0; i < pts.length; i++) {
                    x0 = Math.min(x0, pts[i].x); x1 = Math.max(x1, pts[i].x);
                    y0 = Math.min(y0, pts[i].y); y1 = Math.max(y1, pts[i].y);
                }
                if (hasHead) {
                    x0 = Math.min(x0, hx); x1 = Math.max(x1, hx);
                    y0 = Math.min(y0, hy); y1 = Math.max(y1, hy);
                }
                if (x0 > x1) {
                    boxW = 1;
                    boxH = 1;
                    return;
                }
                // Fixed-size canvas that only moves (resizing a canvas every frame is what made this slow):
                // when the pet gets near the edge of the box, the box is re-centred on it.
                var pad = Math.max(root.maxWidth + 28, rips.length > 0 ? 110 : 0, root.fxOn("swarm") ? 110 : 0);   // a scattered swarm reaches ~100 px
                var S = root.petLife > 700 ? 760 : 360;   // a bigger canvas only while a shape is being drawn
                var fits = boxW === S && x0 - pad >= boxX && y0 - pad >= boxY && x1 + pad <= boxX + S && y1 + pad <= boxY + S;
                if (fits)
                    return;
                boxX = Math.round(((x0 + x1) / 2 - S / 2) / 32) * 32;
                boxY = Math.round(((y0 + y1) / 2 - S / 2) / 32) * 32;
                boxW = S;
                boxH = S;
            }

            function repaint() {
                pglow.requestPaint();
                pcore.requestPaint();
            }

            Connections {
                target: root
                function onPetSeqChanged() {
                    var now = Date.now();
                    var lx = root.petX - host.modelData.x;
                    var ly = root.petY - host.modelData.y;
                    var inside = !root.petHide && root.petBehind === behindLayer && lx >= -20 && ly >= -20 && lx <= host.width + 20 && ly <= host.height + 20;
                    while (petI.pts.length > 0 && now - petI.pts[0].t > root.petLife)
                        petI.pts.shift();
                    if (petI.rips.length > 0)
                        petI.rips = petI.rips.filter(function (r) { return now - r.t < r.dur; });
                    if (!inside && petI.pts.length === 0 && petI.rips.length === 0 && !petI.drawn)
                        return;   // nothing here to draw or to erase
                    petI.hasHead = inside;
                    if (inside) {
                        var pl = petI.pts.length;   // a long jump: cut the tail (a huge streak is slow to paint)
                        if (pl > 0 && Math.abs(petI.pts[pl - 1].x - lx) + Math.abs(petI.pts[pl - 1].y - ly) > 130)
                            petI.pts = [];
                        petI.hx = lx;
                        petI.hy = ly;
                        petI.pts.push({ x: lx, y: ly, t: now, v: root.petV, d: false, id: root.petSeq });
                        while (petI.pts.length > Math.ceil(root.petLife / 12) + 12)
                            petI.pts.shift();
                    }
                    petI.drawn = inside || petI.pts.length > 0 || petI.rips.length > 0;   // false after the last erase, so the next call returns early
                    petI.updateBox();
                    petI.repaint();
                }
                function onPetRing(x, y, sz, dur) {
                    if (root.petBehind !== behindLayer)
                        return;
                    var rx = x - host.modelData.x, ry = y - host.modelData.y;
                    if (rx < -80 || ry < -80 || rx > host.width + 80 || ry > host.height + 80)
                        return;
                    petI.rips = petI.rips.concat([{ x: rx, y: ry, t: Date.now(), dur: dur, sz: sz * 0.65, a: 0.45 }]).slice(-6);
                    petI.drawn = true;
                    petI.updateBox();
                    petI.repaint();
                }
                function onPetBurst(x, y) {
                    if (root.petBehind !== behindLayer)
                        return;
                    var bx = x - host.modelData.x, by = y - host.modelData.y;
                    if (bx < -40 || by < -40 || bx > host.width + 40 || by > host.height + 40)
                        return;
                    var t0 = Date.now(), np = [];
                    for (var i = 0; i < 44; i++) {
                        var ang = Math.random() * Math.PI * 2;
                        var sp = 60 + Math.random() * 170;
                        np.push({ x: bx, y: by, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
                                  t: t0, life: 500 + Math.random() * 500, s: 0.9 + Math.random() * 0.9, cf: Math.random() });
                    }
                    petI.bcx = bx;
                    petI.bcy = by;
                    petI.parts = np;
                    petI.rips = [{ x: bx, y: by, t: t0, dur: 700, sz: 1.0, a: 0.6 }];
                    petI.pts = [];
                    petI.hasHead = false;
                    petI.drawn = true;
                    petI.bursting = true;
                    petI.updateBox();
                    pglow.requestPaint();   // paints nothing: pts and head are gone, sparks are drawn on the core canvas
                    pcore.requestPaint();
                    burstTick.start();
                }
                function onPetOnChanged() {
                    if (!root.petOn) {
                        petI.rips = petI.parts.length > 0 ? petI.rips : [];
                        petI.pts = [];
                        petI.hasHead = false;
                        petI.updateBox();
                        petI.repaint();
                    }
                }
            }

            Timer {
                id: burstTick
                interval: 33
                repeat: true
                onTriggered: {
                    var now = Date.now();
                    petI.parts = petI.parts.filter(function (s) { return now - s.t < s.life; });
                    petI.rips = petI.rips.filter(function (r) { return now - r.t < r.dur; });
                    petI.updateBox();
                    pcore.requestPaint();   // only the core canvas while the sparks fly (half the cost)
                    if (petI.parts.length === 0 && petI.rips.length === 0) {
                        petI.drawn = false;
                        petI.bursting = false;
                        petI.repaint();
                        running = false;
                    }
                }
            }

            Layer { id: pglow; owner: petI; pet: true; sz: root.petSize; lutOver: root.petGlowLut; opacity: 0.3 }
            Layer { id: pcore; owner: petI; pet: true; sz: root.petSize; lutOver: root.petCoreLut; isCore: true; opacity: 0.9 }
    }

    // One layer (glow or core) of a wild swarm: a canvas that follows the swarm (a fixed-size box that only moves).
    component WildLayer: Canvas {
        property var view
        property bool isCore: false
        renderTarget: Canvas.Image
        opacity: isCore ? 0.9 : 0.3
        x: view.boxX
        y: view.boxY
        width: view.boxW
        height: view.boxH

        onPaint: {
            var ctx = getContext("2d");
            ctx.setTransform(1, 0, 0, 1, 0, 0);
            ctx.clearRect(0, 0, width, height);
            var sw = view.current;
            if (!sw || !view.drawn)
                return;
            ctx.setTransform(1, 0, 0, 1, -view.boxX, -view.boxY);
            var lut = root.wildLuts[sw.i];
            if (!lut || lut.length === 0)
                return;
            root.drawLights(ctx, sw.flies, lut[0], sw.moodKind, sw.moodA, sw.mixTint, sw.mixA, isCore, Date.now(),
                            view.host.modelData.x, view.host.modelData.y, sw.fade * sw.dim);
        }
    }

    // One wild swarm on one screen (in front of the windows). idx = which wild swarm.
    component WildView: Item {
        id: wv
        required property var host
        property int idx: 0
        anchors.fill: parent

        property var current: null
        property int boxX: 0
        property int boxY: 0
        property int boxW: 420
        property int boxH: 420
        property bool drawn: false   // something is on the canvas that must still be erased

        function update() {
            var sw = root.wild.length > idx ? root.wild[idx] : null;
            current = sw;
            var lx = sw ? sw.x - host.modelData.x : 0;
            var ly = sw ? sw.y - host.modelData.y : 0;
            var inside = sw !== null && !root.petHide && sw.fade > 0.02 && lx > -150 && ly > -150 && lx < host.width + 150 && ly < host.height + 150;
            if (!inside && !drawn)
                return;
            if (inside) {
                var S = sw.mode === "join" ? 720 : 420;
                var pad = 130;
                var fits = boxW === S && lx - pad >= boxX && ly - pad >= boxY && lx + pad <= boxX + S && ly + pad <= boxY + S;
                if (!fits) {
                    boxX = Math.round((lx - S / 2) / 32) * 32;
                    boxY = Math.round((ly - S / 2) / 32) * 32;
                    boxW = S;
                    boxH = S;
                }
            }
            drawn = inside;
            wglow.requestPaint();
            wcore.requestPaint();
        }

        Connections {
            target: root
            function onWildSeqChanged() { wv.update(); }
        }

        WildLayer { id: wglow; view: wv }
        WildLayer { id: wcore; view: wv; isCore: true }
    }

    Variants {
        model: root.overlayOn ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: !root.remapGap

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "power-fx"
            mask: Region {}   // empty input region = clicks pass through

            // Tile effects for this screen: a canvas that covers only the area the effects use.
            Item {
                id: tiles
                anchors.fill: parent

                property int boxX: 0
                property int boxY: 0
                property int boxW: 1
                property int boxH: 1

                function mine() {
                    var now = Date.now();
                    var out = [];
                    for (var i = 0; i < root.fxList.length; i++) {
                        var e = root.fxList[i];
                        if ((e.mon === win.modelData.name || e.mon === "*") && now - e.t < e.dur)
                            out.push(e);
                    }
                    return out;
                }

                // true while something needs redrawing every frame (a held tint does not)
                function animating() {
                    var l = mine();
                    var now = Date.now();
                    for (var i = 0; i < l.length; i++)
                        if (!(l[i].hold && !l[i].endT && now - l[i].t > 300))
                            return true;
                    return false;
                }

                function onlyBreathing() {
                    var l = mine();
                    for (var i = 0; i < l.length; i++)
                        if (l[i].kind !== "urgent" && !l[i].hold)
                            return false;
                    return true;
                }

                Component.onCompleted: {
                    if (mine().length > 0)
                        fxTick.running = true;
                }

                function updateBox() {
                    var l = mine();
                    if (l.length === 0) {
                        boxW = 1;
                        boxH = 1;
                        return;
                    }
                    var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                    for (var i = 0; i < l.length; i++) {
                        x0 = Math.min(x0, l[i].bx0 - win.modelData.x);
                        y0 = Math.min(y0, l[i].by0 - win.modelData.y);
                        x1 = Math.max(x1, l[i].bx1 - win.modelData.x);
                        y1 = Math.max(y1, l[i].by1 - win.modelData.y);
                    }
                    var g = 64;
                    var nx = Math.max(0, Math.floor(x0 / g) * g);
                    var ny = Math.max(0, Math.floor(y0 / g) * g);
                    var nr = Math.min(win.width, Math.ceil(x1 / g) * g);
                    var nb = Math.min(win.height, Math.ceil(y1 / g) * g);
                    if (nr <= nx || nb <= ny) {
                        boxW = 1;
                        boxH = 1;
                        return;
                    }
                    boxX = nx; boxY = ny; boxW = nr - nx; boxH = nb - ny;
                }

                Canvas {
                    id: fxCanvas
                    renderTarget: Canvas.Image
                    x: tiles.boxX
                    y: tiles.boxY
                    width: tiles.boxW
                    height: tiles.boxH
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.setTransform(1, 0, 0, 1, 0, 0);
                        ctx.clearRect(0, 0, width, height);
                        var l = tiles.mine();
                        if (l.length === 0 || root.glowLut.length === 0)
                            return;
                        ctx.setTransform(1, 0, 0, 1, -(win.modelData.x + tiles.boxX), -(win.modelData.y + tiles.boxY));
                        var now = Date.now();
                        for (var i = 0; i < l.length; i++)
                            root.drawFx(ctx, l[i], now, { x: win.modelData.x, y: win.modelData.y, w: win.width, h: win.height });
                    }
                }

                Connections {
                    target: root
                    function onFxSeqChanged() {
                        fxTick.running = true;
                    }
                }

                // Runs only while a tile effect is playing.
                Timer {
                    id: fxTick
                    interval: 16
                    repeat: true
                    onTriggered: {
                        tiles.updateBox();
                        fxCanvas.requestPaint();
                        interval = tiles.onlyBreathing() ? 50 : 16;   // slow breathing needs fewer frames
                        if (!tiles.animating())
                            running = false;
                    }
                }
            }

            // The desktop pet (see PetView): in front of the windows. A second one, under the windows, is at the end of the file.
            PetView { host: win; behindLayer: false }

            // The wild swarms (see wildStep), in front of the windows.
            Repeater {
                model: Math.max(0, root.swarmFlocks - 1)
                WildView {
                    required property int index
                    host: win
                    idx: index
                }
            }

            Item {
                id: trail
                anchors.fill: parent

                property var pts: []     // trail points {x, y, t, v}
                property var parts: []   // sparkles
                property var rips: []    // click ripples {x, y, t}
                property var ext: []     // touchscreen fingers 1..9, by number: {pts, hasHead, hx, hy, upT} or null
                // The canvases only cover the area the trail occupies (snapped to a 64 px grid).
                // The area grows at once but shrinks only when much smaller, so it does not
                // resize every frame and never clips the tail.
                property int boxX: 0
                property int boxY: 0
                property int boxW: 1
                property int boxH: 1
                property int cboxX: 0          // smaller box for the glow and core layers (see updateCBox)
                property int cboxY: 0
                property int cboxW: 1
                property int cboxH: 1
                property bool hasHead: false   // the cursor is on this screen
                property real hx: 0            // cursor position on this screen
                property real hy: 0
                property string edgeState: ""   // which screen edge the cursor touches now

                // Box of the glow and core layers: they draw only points younger than lifeMs (the ghost keeps
                // them 1100 ms) and no touch fingers, so their canvas is smaller. Same grow/shrink rule.
                function updateCBox() {
                    var now = Date.now();
                    var life = root.lifeMs;
                    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
                    var any = false;
                    var i, e;
                    var f0 = 0;
                    while (f0 < pts.length && now - pts[f0].t >= life)
                        f0++;
                    for (i = Math.max(0, f0 - 1); i < pts.length; i++) {   // one dead point before: the first curve starts between it and the first live one
                        e = pts[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    for (i = 0; i < parts.length; i++) {
                        e = parts[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    for (i = 0; i < rips.length; i++) {
                        e = rips[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    if (hasHead) {
                        if (hx < x0) x0 = hx;
                        if (hx > x1) x1 = hx;
                        if (hy < y0) y0 = hy;
                        if (hy > y1) y1 = hy;
                        any = true;
                    }
                    if (!any) {
                        cboxW = 1;
                        cboxH = 1;
                        return;
                    }
                    var pad = root.maxWidth + 56;
                    var g = 64;
                    var nx = Math.floor((x0 - pad) / g) * g;
                    var ny = Math.floor((y0 - pad) / g) * g;
                    var nr = Math.ceil((x1 + pad) / g) * g;
                    var nb = Math.ceil((y1 + pad) / g) * g;
                    var cr = cboxX + cboxW;
                    var cb = cboxY + cboxH;
                    var fits = nx >= cboxX && ny >= cboxY && nr <= cr && nb <= cb;
                    var muchSmaller = (nr - nx) * 2 < cboxW || (nb - ny) * 2 < cboxH;
                    if (fits && !muchSmaller)
                        return;
                    if (fits) {
                        cboxX = nx; cboxY = ny; cboxW = nr - nx; cboxH = nb - ny;
                    } else {
                        var init = cboxW > 1;
                        var ux = Math.min(nx, init ? cboxX : nx) - g;
                        var uy = Math.min(ny, init ? cboxY : ny) - g;
                        var ur = Math.max(nr, init ? cr : nr) + g;
                        var ub = Math.max(nb, init ? cb : nb) + g;
                        cboxX = ux; cboxY = uy; cboxW = ur - ux; cboxH = ub - uy;
                    }
                }

                function updateBox() {
                    updateCBox();
                    // bounds of every point, sparkle, ripple, head and touch finger (no arrays are built)
                    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
                    var any = false;
                    var i, e;
                    for (i = 0; i < pts.length; i++) {
                        e = pts[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    for (i = 0; i < parts.length; i++) {
                        e = parts[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    for (i = 0; i < rips.length; i++) {
                        e = rips[i];
                        if (e.x < x0) x0 = e.x;
                        if (e.x > x1) x1 = e.x;
                        if (e.y < y0) y0 = e.y;
                        if (e.y > y1) y1 = e.y;
                        any = true;
                    }
                    if (hasHead) {
                        if (hx < x0) x0 = hx;
                        if (hx > x1) x1 = hx;
                        if (hy < y0) y0 = hy;
                        if (hy > y1) y1 = hy;
                        any = true;
                    }
                    for (var xi = 0; xi < ext.length; xi++) {   // the other touchscreen fingers
                        var xf = ext[xi];
                        if (!xf)
                            continue;
                        for (i = 0; i < xf.pts.length; i++) {
                            e = xf.pts[i];
                            if (e.x < x0) x0 = e.x;
                            if (e.x > x1) x1 = e.x;
                            if (e.y < y0) y0 = e.y;
                            if (e.y > y1) y1 = e.y;
                            any = true;
                        }
                        if (xf.hasHead) {
                            if (xf.hx < x0) x0 = xf.hx;
                            if (xf.hx > x1) x1 = xf.hx;
                            if (xf.hy < y0) y0 = xf.hy;
                            if (xf.hy > y1) y1 = xf.hy;
                            any = true;
                        }
                    }
                    if (!any) {
                        boxW = 1;
                        boxH = 1;
                        return;
                    }
                    var pad = root.maxWidth + 56;   // room for thick tail + sparkle drift
                    var g = 64;
                    var nx = Math.floor((x0 - pad) / g) * g;
                    var ny = Math.floor((y0 - pad) / g) * g;
                    var nr = Math.ceil((x1 + pad) / g) * g;
                    var nb = Math.ceil((y1 + pad) / g) * g;
                    var cr = boxX + boxW;
                    var cb = boxY + boxH;
                    var fits = nx >= boxX && ny >= boxY && nr <= cr && nb <= cb;
                    var muchSmaller = (nr - nx) * 2 < boxW || (nb - ny) * 2 < boxH;
                    if (fits && !muchSmaller)
                        return;
                    if (fits) {
                        // shrink to the needed area
                        boxX = nx; boxY = ny; boxW = nr - nx; boxH = nb - ny;
                    } else {
                        // grow to hold both the old area and the needed area, plus slack
                        var init = boxW > 1;
                        var ux = Math.min(nx, init ? boxX : nx) - g;
                        var uy = Math.min(ny, init ? boxY : ny) - g;
                        var ur = Math.max(nr, init ? cr : nr) + g;
                        var ub = Math.max(nb, init ? cb : nb) + g;
                        boxX = ux; boxY = uy; boxW = ur - ux; boxH = ub - uy;
                    }
                }

                // Sparkles come per distance moved, not per pointer event: sparkleChance per 8 px of path
                // (so the amount does not depend on the mouse's report rate). The fraction carries over.
                property real spAcc: 0
                property int frameNo: 0    // counts ticks (screen frames); sparkles spawn once per frame
                property int spFrame: -1
                function spawn(x0, y0, x1, y1, dist) {
                    if (!root.fxOn("sparkles") || root.sparkleChance <= 0) {
                        spAcc = 0;
                        return;
                    }
                    spAcc = Math.min(spAcc + Math.min(dist, 60) / 8 * root.sparkleChance, 8);   // a long jump is capped
                    if (spFrame === frameNo)
                        return;   // already spawned this frame: the distance waits in spAcc
                    spFrame = frameNo;
                    var n = Math.floor(spAcc);   // at most 8 per frame
                    spAcc -= n;
                    for (var k = 0; k < n && parts.length <= 400; k++) {
                        var f = (k + 1) / n;   // spread along the path from the old point to the new one
                        spawnOne({ x: x0 + (x1 - x0) * f, y: y0 + (y1 - y0) * f });
                    }
                }

                function spawnOne(pt) {
                    var ang = Math.random() * Math.PI * 2;
                    var sp = 8 + Math.random() * 28;
                    parts.push({
                        x: pt.x + (Math.random() - 0.5) * 8,
                        y: pt.y + (Math.random() - 0.5) * 8,
                        vx: Math.cos(ang) * sp,
                        vy: Math.sin(ang) * sp - 6,
                        t: Date.now(),
                        life: 175 + Math.random() * 225,
                        s: 0.32 + Math.random() * 0.52,
                        cf: Math.random()
                    });
                }

                function repaint() {
                    ghost.requestPaint();
                    glow.requestPaint();
                    core.requestPaint();
                }

                Connections {
                    target: root
                    function onClicksChanged() {
                        if (!root.fxOn("clicks") || root.clickMon !== win.modelData.name)
                            return;
                        trail.rips.push({ x: root.clickX - win.modelData.x, y: root.clickY - win.modelData.y, t: Date.now(), dur: root.rippleMs, sz: 1, shape: root.clickShape });
                        if (trail.rips.length > 8)
                            trail.rips.shift();
                        tick.running = true;
                    }
                    function onScrollsChanged() {
                        if (trail.hasHead)
                            tick.running = true;
                    }
                    function onTfSeqChanged() {   // a point of finger 1..9
                        if (root.tfMon !== win.modelData.name)
                            return;
                        var lx = root.tfX - win.modelData.x;
                        var ly = root.tfY - win.modelData.y;
                        var e = trail.ext[root.tfIdx];
                        if (!e || root.tfNew) {   // a new touch starts a fresh stroke
                            // a tap has no path: start with a point 2 px to the left so even a tap leaves a short ghost
                            e = { pts: [{ x: lx - 2, y: ly, t: Date.now(), v: 0, d: false, id: root.tfSeq }], hasHead: true, hx: lx, hy: ly, upT: 0 };
                            trail.ext[root.tfIdx] = e;
                        }
                        e.hasHead = true;
                        e.upT = 0;
                        e.hx = lx;
                        e.hy = ly;
                        var now = Date.now();
                        var n = e.pts.length;
                        var v = 0;
                        var dup = false;
                        if (n > 0) {
                            var prev = e.pts[n - 1];
                            var dx = prev.x - lx;
                            var dy = prev.y - ly;
                            var d2 = dx * dx + dy * dy;
                            if (d2 < 1.5)
                                dup = true;
                            else
                                v = prev.v * 0.6 + (Math.sqrt(d2) / Math.max(1, now - prev.t)) * 0.4;
                        }
                        if (!dup) {
                            e.pts.push({ x: lx, y: ly, t: now, v: v, d: false, id: root.tfSeq });
                            if (e.pts.length > 220)
                                e.pts.shift();
                            tick.running = true;
                        }
                        if (!tick.running) {
                            trail.updateBox();
                            trail.repaint();
                        }
                    }
                    function onTcSeqChanged() {   // tap of a touchscreen finger: the same ring as a click
                        var e = trail.ext[root.tcIdx];
                        if (!e || !root.fxOn("clicks"))
                            return;
                        trail.rips.push({ x: e.hx, y: e.hy, t: Date.now(), dur: root.rippleMs, sz: 1, shape: "circle" });
                        if (trail.rips.length > 8)
                            trail.rips.shift();
                        tick.running = true;
                    }
                    function onTfUpSeqChanged() {   // finger lifted: the head goes shortly, the tail fades by itself
                        var e = trail.ext[root.tfUpIdx];
                        if (!e)
                            return;
                        e.upT = Date.now();
                        tick.running = true;
                    }
                    function onPopsChanged() {
                        if (!root.fxOn("pop") || root.popMon !== win.modelData.name)
                            return;
                        var px = root.popX - win.modelData.x;
                        var py = root.popY - win.modelData.y;
                        trail.rips.push({ x: px, y: py, t: Date.now(), dur: 320, sz: 0.45 });
                        if (trail.rips.length > 8)
                            trail.rips.shift();
                        for (var b = 0; b < 10; b++)
                            trail.spawnOne({ x: px, y: py });
                        tick.running = true;
                    }
                    function onSeqChanged() {
                        if (root.mon !== win.modelData.name) {
                            // cursor left this screen: remove the head here
                            if (trail.hasHead) {
                                trail.hasHead = false;
                                trail.edgeState = "";
                                if (!tick.running) {
                                    trail.updateBox();
                                    trail.repaint();
                                }
                            }
                            return;
                        }
                        var lx = root.cx - win.modelData.x;
                        var ly = root.cy - win.modelData.y;
                        if (Date.now() < root.holdUntil) {   // the pointer is walking to a held finger: move the head, draw no trail
                            trail.hasHead = true;
                            trail.hx = lx;
                            trail.hy = ly;
                            if (!tick.running) {
                                trail.updateBox();
                                trail.repaint();
                            }
                            return;
                        }
                        var jumpFrom = null;   // the pointer was moved by something other than the mouse (hint keys, window swap)
                        if (trail.hasHead && Math.abs(lx - trail.hx) + Math.abs(ly - trail.hy) > 150 &&
                                (trail.pts.length === 0 || Date.now() - trail.pts[trail.pts.length - 1].t > 100))
                            jumpFrom = { x: trail.hx, y: trail.hy };
                        trail.hasHead = true;
                        trail.hx = lx;
                        trail.hy = ly;
                        var edge = "";
                        if (lx <= 1) edge = "l";
                        else if (lx >= win.width - 2) edge = "r";
                        else if (ly <= 1) edge = "t";
                        else if (ly >= win.height - 2) edge = "b";
                        if (root.fxOn("edgeglow") && edge !== "" && edge !== trail.edgeState) {   // just touched an edge
                            trail.rips.push({ x: Math.max(0, Math.min(win.width, lx)), y: Math.max(0, Math.min(win.height, ly)),
                                              t: Date.now(), dur: 500, sz: 1, edge: true });
                            if (trail.rips.length > 8)
                                trail.rips.shift();
                            tick.running = true;
                        }
                        trail.edgeState = edge;
                        var now = Date.now();
                        var n = trail.pts.length;
                        var v = 0;
                        var dup = false;
                        if (n > 0) {
                            var prev = trail.pts[n - 1];
                            var dx = prev.x - lx;
                            var dy = prev.y - ly;
                            var d2 = dx * dx + dy * dy;
                            if (d2 < 1.5)   // skip near-duplicates: fewer strokes
                                dup = true;
                            else   // speed in px/ms, smoothed so the width changes gently
                                v = prev.v * 0.6 + (Math.sqrt(d2) / Math.max(1, now - prev.t)) * 0.4;
                        }
                        if (!dup) {
                            if (root.fxOn("kbtrail") && !jumpFrom && n > 0 && now - prev.t > 40 && now - prev.t < 400) {   // slow, stepwise samples (keyboard cursor): fill in between
                                var sdist = Math.sqrt((lx - prev.x) * (lx - prev.x) + (ly - prev.y) * (ly - prev.y));
                                if (sdist > 8 && sdist <= 150) {
                                    var sn = Math.min(10, Math.ceil(sdist / 4));
                                    for (var si = 1; si < sn; si++) {
                                        var sf = si / sn;
                                        trail.pts.push({ x: prev.x + (lx - prev.x) * sf, y: prev.y + (ly - prev.y) * sf,
                                                         t: prev.t + (now - prev.t) * sf, v: prev.v + (v - prev.v) * sf, d: root.dragging, id: root.seq });
                                    }
                                }
                            }
                            if (jumpFrom) {   // draw a quick streak from the old spot to the new one
                                var jn = 10;
                                var jv = Math.min(2.5, Math.sqrt((lx - jumpFrom.x) * (lx - jumpFrom.x) + (ly - jumpFrom.y) * (ly - jumpFrom.y)) / 140);
                                for (var ji = 0; ji < jn; ji++) {
                                    var jf = ji / jn;
                                    trail.pts.push({ x: jumpFrom.x + (lx - jumpFrom.x) * jf, y: jumpFrom.y + (ly - jumpFrom.y) * jf,
                                                     t: now - 140 * (1 - jf), v: jv, d: false, id: root.seq });
                                }
                            }
                            trail.pts.push({ x: lx, y: ly, t: now, v: v, d: root.dragging, id: root.seq });
                            // sparkles come off the cursor end, per distance moved (the first point of a stroke counts 8 px)
                            if (n > 0 && !jumpFrom)
                                trail.spawn(prev.x, prev.y, lx, ly, Math.sqrt(d2));
                            else
                                trail.spawn(lx, ly, lx, ly, jumpFrom ? 0 : 8);
                            if (trail.pts.length > 220)
                                trail.pts.shift();
                            tick.running = true;
                        }
                        if (!tick.running) {   // nothing animating: still redraw the resting head
                            trail.updateBox();
                            trail.repaint();
                        }
                    }
                }

                // Runs only while there is something to draw; stops when everything has faded.
                // One tick per screen refresh (FrameAnimation follows the display's rate, not a fixed 16 ms).
                FrameAnimation {
                    id: tick
                    onTriggered: {
                        var now = Date.now();
                        trail.frameNo++;
                        var tp = trail.pts, k0 = 0;
                        while (k0 < tp.length && now - tp[k0].t > root.ghostMs)
                            k0++;
                        if (k0 > 0)
                            tp.splice(0, k0);
                        var ps = trail.parts, pw = 0;   // drop expired sparkles and ripples in place
                        for (var pr = 0; pr < ps.length; pr++)
                            if (now - ps[pr].t < ps[pr].life)
                                ps[pw++] = ps[pr];
                        if (pw !== ps.length)
                            ps.length = pw;
                        var rs = trail.rips;
                        pw = 0;
                        for (var rr = 0; rr < rs.length; rr++)
                            if (now - rs[rr].t < rs[rr].dur)
                                rs[pw++] = rs[rr];
                        if (pw !== rs.length)
                            rs.length = pw;
                        var extBusy = false;   // a touchscreen finger (1..9) still has a tail, or a head waiting to go
                        for (var xi = 0; xi < trail.ext.length; xi++) {
                            var xe = trail.ext[xi];
                            if (!xe)
                                continue;
                            while (xe.pts.length > 0 && now - xe.pts[0].t > root.touchGhostMs)
                                xe.pts.shift();
                            if (xe.upT > 0 && now - xe.upT > 350)
                                xe.hasHead = false;
                            if (!xe.hasHead && xe.pts.length === 0)
                                trail.ext[xi] = null;
                            else if (xe.pts.length > 0 || xe.upT > 0)
                                extBusy = true;
                        }
                        trail.updateBox();
                        trail.repaint();
                        if (trail.pts.length === 0 && trail.parts.length === 0 && trail.rips.length === 0 && !extBusy
                                && !(trail.hasHead && now - root.scrollT < 350))
                            running = false;
                    }
                }

                Layer { id: ghost; owner: trail; ghost: true; opacity: root.fxOn("afterimage") ? 0.14 : 0 }
                Layer { id: glow; owner: trail; small: true; opacity: 0.3 }
                Layer { id: core; owner: trail; small: true; isCore: true; opacity: 0.9 }
            }
        }
    }

    // The same pet on the bottom layer: under every window (tiles cover it), above the wallpaper.
    // The pet goes here when the cursor has annoyed it for too long. Exists only while the pet is on.
    Variants {
        model: root.petOn ? Quickshell.screens : []

        PanelWindow {
            id: backWin
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "power-fx-pet-back"
            mask: Region {}

            PetView { host: backWin; behindLayer: true }
        }
    }
}
