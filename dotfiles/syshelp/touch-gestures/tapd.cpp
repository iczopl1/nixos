// tapd: touchscreen taps, long-press and pinch for mango. Complements lisgd (swipes).
// Reads raw evdev multitouch events (protocol B). No libraries. Runs commands with sh -c.
//   build: g++ -O2 -std=c++17 -Wall -Wextra -o tapd tapd.cpp
//   usage: tapd /dev/input/by-path/...-event
// Gestures (one per touch session, i.e. from first finger down to last finger up):
//   3/4/5 finger tap  : short, little movement      -> CMD_TAP3 / CMD_TAP4 / CMD_TAP5
//   1 finger long press: held LONG_MS, no movement   -> CMD_LONG   (fires while still held)
//   2 finger pinch    : distance changes by STEP     -> CMD_PINCH_OUT / CMD_PINCH_IN (repeats per step)
// Commands come from the environment so the wrapper script owns the policy.
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;
static constexpr int MAXSLOT = 10;
static constexpr int TAP_MS = 350;      // max duration of a tap
static constexpr int LONG_MS = 500;     // long-press time
static constexpr double MOVE_FRAC = 0.03;   // movement allowed, fraction of screen diagonal
static constexpr double PINCH_STEP = 0.20;  // distance change per pinch step

struct Slot { bool down = false; int x = 0, y = 0, sx = 0, sy = 0; };

static Slot slots[MAXSLOT];
static int cur = 0;                 // current slot
static int maxFingers = 0;          // peak simultaneous fingers this session
static bool inSession = false, fired = false, moved = false;
static Clock::time_point t0;
static double diag = 1000;          // screen diagonal in device units
static double pinchBase = 0;        // two-finger distance baseline
static double rangeX = 1920, rangeY = 1080;   // device units per axis
static double pxW = 1920, pxH = 1080;         // screen pixels (env PX_W / PX_H)
static bool pinched = false;        // a pinch step fired this session: no drag afterwards
static bool dragRef = false, dragging = false;   // 2-finger window drag state
static double refX = 0, refY = 0, accX = 0, accY = 0;
static double minX = 0, minY = 0;   // device axis minimums
static int dragTarget = -1;         // client id under both fingers, or -1
static Clock::time_point lastEmit;
static int gapMode = 0, gapTarget = -1;     // 'V' / 'H' gap under the first finger, and the tile to resize
static bool gapDrag = false;
static double gapRef = 0, gapAcc = 0;
static Clock::time_point gapLast;
static bool kbShown = false;                // on-screen keyboard visible when a 3-finger drag began
static bool gapProbed = false;             // gap lookup done for this touch (done lazily, on first movement)
static constexpr double GAP_TOL = 12;      // px of extra grab zone on each side of the gap
static constexpr double GAP_MAX = 40;       // widest gap treated as a tile border
static constexpr double GAP_DEAD_PX = 8;    // travel before the resize starts
static constexpr int DRAG_FINGERS = 3;      // fingers needed to drag a window
static constexpr double DRAG_DEAD = 0.02;   // centroid travel before a drag starts (fraction of diagonal)
static constexpr int EMIT_MS = 16;          // max one move command per 16 ms
static bool dropping = false;       // skipping events after SYN_DROPPED

static const char* env(const char* k) { const char* v = getenv(k); return (v && *v) ? v : nullptr; }

static void run(const char* var) {
    const char* cmd = env(var);
    if (!cmd) return;
    pid_t p = fork();
    if (p == 0) {
        setsid();
        signal(SIGCHLD, SIG_DFL);   // SIG_IGN is inherited by exec and breaks `wait` in the command
        execl("/bin/sh", "sh", "-c", cmd, (char*)nullptr);
        _exit(127);
    }
}

static int fingers() { int n = 0; for (auto& s : slots) n += s.down; return n; }

static double pinchDist() {
    int a = -1, b = -1;
    for (int i = 0; i < MAXSLOT; i++) if (slots[i].down) { if (a < 0) a = i; else if (b < 0) b = i; }
    if (a < 0 || b < 0) return 0;
    return std::hypot(slots[a].x - slots[b].x, slots[a].y - slots[b].y);
}

static void checkMoved() {
    for (auto& s : slots)
        if (s.down && s.sx >= 0 && s.sy >= 0 && std::hypot(s.x - s.sx, s.y - s.sy) > MOVE_FRAC * diag) moved = true;
}

static long msSince() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
}

// ---- swipes: direction from start->end centroid, edge from where the first finger landed ----
// Directions are in the DEVICE frame: R = +x, L = -x, D = +y (down), U = -y (up).
// Command lookup: CMD_SW_<fingers><dir>_<edge> (edge L/R/T/B) first, then CMD_SW_<fingers><dir>.
static double stCx = 0, stCy = 0, enCx = 0, enCy = 0, fx = 0, fy = 0;
static constexpr double SWIPE_MIN_PX = 60;   // shortest swipe
static constexpr long SWIPE_MAX_MS = 1500;   // slowest swipe
static constexpr double EDGE_PX = 110;       // width of the edge zone

static void trySwipe() {
    double dxp = (enCx - stCx) * pxW / rangeX, dyp = (enCy - stCy) * pxH / rangeY;
    double len = std::hypot(dxp, dyp);
    if (len < 40) return;
    char dir = std::fabs(dxp) >= std::fabs(dyp) ? (dxp > 0 ? 'R' : 'L') : (dyp > 0 ? 'D' : 'U');
    double nx = (fx - minX) * pxW / rangeX, ny = (fy - minY) * pxH / rangeY;
    char edge = nx < EDGE_PX ? 'L' : nx > pxW - EDGE_PX ? 'R' : ny < EDGE_PX ? 'T' : ny > pxH - EDGE_PX ? 'B' : '-';
    fprintf(stderr, "swipe f=%d dir=%c edge=%c len=%.0fpx start=(%.0f,%.0f)\n", maxFingers, dir, edge, len, nx, ny);
    if (len < SWIPE_MIN_PX) return;
    char var[40];
    if (edge != '-') {
        snprintf(var, sizeof var, "CMD_SW_%d%c_%c", maxFingers, dir, edge);
        if (env(var)) { run(var); return; }
    }
    snprintf(var, sizeof var, "CMD_SW_%d%c", maxFingers, dir);
    run(var);
}

static std::string capture(const std::string& cmd);
static bool getNum(const std::string& o, const char* key, double& v);
static int hitTest(bool floatingOnly, const double* dxs, const double* dys, int need, bool inclFs = false);

// 1-finger tap: mango does not focus a window on touch, so do it here (never over menus / keyboard).
static void focusTap() {
    std::string layers = capture("mmsg get all-layers 2>/dev/null");
    for (const char* bad : {"qs-menu", "wvkbd", "selection"})
        if (layers.find(bad) != std::string::npos) return;
    int id = hitTest(false, &fx, &fy, 1, true);   // fullscreen tile counts: it covers the tiles under it
    if (id < 0) return;
    char arg[32];
    snprintf(arg, sizeof arg, "client,%d", id);   // `focusid client,ID` is the form that works
    // Overview = every tag of the monitor is active at once. A tap there must also leave overview (a click does).
    const char* mn = env("TOUCH_MON");
    std::string mj = capture(std::string("mmsg get monitor ") + (mn ? mn : "eDP-1") + " 2>/dev/null");
    double tagNum = 0; getNum(mj, "tag_num", tagNum);
    int act = 0;
    for (size_t q = mj.find("\"is_active\":true"); q != std::string::npos; q = mj.find("\"is_active\":true", q + 1)) act++;
    bool overview = tagNum >= 2 && act >= (int)tagNum;
    fprintf(stderr, "focus tap -> client %d%s\n", id, overview ? " (overview: leaving)" : "");
    pid_t p = fork();
    if (p == 0) {
        setsid();
        signal(SIGCHLD, SIG_DFL);
        if (overview) {
            char cmd[160];
            snprintf(cmd, sizeof cmd, "mmsg dispatch focusid %s; mmsg dispatch toggleoverview; mmsg dispatch setkeymode,default", arg);
            execl("/bin/sh", "sh", "-c", cmd, (char*)nullptr);
        }
        execlp("mmsg", "mmsg", "dispatch", "focusid", arg, (char*)nullptr);
        _exit(127);
    }
}

static void endSession() {
    if (inSession && !fired && !moved && maxFingers == 1 && msSince() <= TAP_MS) {
        focusTap();
    } else if (inSession && !fired && !moved && maxFingers >= 3 && maxFingers <= 5 && msSince() <= TAP_MS) {
        char var[24];
        snprintf(var, sizeof var, "CMD_TAP%d", maxFingers);
        run(var);
    } else if (inSession && !fired && !pinched && !dragging && !gapMode && maxFingers >= 1 && msSince() <= SWIPE_MAX_MS) {
        trySwipe();
    }
    inSession = false; fired = false; moved = false; maxFingers = 0; pinchBase = 0;
    pinched = false; dragRef = false; dragging = false; gapMode = 0; gapDrag = false; gapProbed = false;
}

// Hold with 1 finger -> CMD_LONG1 (gets TG_X / TG_Y = touch point in global screen pixels).
// Hold with 2 fingers -> CMD_LONG2 (gets TG_CLIENT = id of the window under both fingers).
static void checkLong() {
    if (!inSession || fired || moved || msSince() < LONG_MS) return;
    int n = fingers();
    if (n != maxFingers) return;
    if (n == 1) {
        const char* mn = env("TOUCH_MON");
        std::string m = capture(std::string("mmsg get monitor ") + (mn ? mn : "eDP-1") + " 2>/dev/null");
        double monX = 0, monY = 0, monW = pxW, monH = pxH;
        getNum(m, "x", monX); getNum(m, "y", monY); getNum(m, "width", monW); getNum(m, "height", monH);
        char buf[24];
        snprintf(buf, sizeof buf, "%d", (int)((fx - minX) * monW / rangeX + monX));
        setenv("TG_X", buf, 1);
        snprintf(buf, sizeof buf, "%d", (int)((fy - minY) * monH / rangeY + monY));
        setenv("TG_Y", buf, 1);
        run("CMD_LONG1");
        fired = true;
    } else if (n == 2) {
        int id = hitTest(false, nullptr, nullptr, 2);
        if (id >= 0) {
            char buf[16];
            snprintf(buf, sizeof buf, "%d", id);
            setenv("TG_CLIENT", buf, 1);
            run("CMD_LONG2");
        }
        fired = true;
    }
}

static void resetAll() {
    for (auto& s : slots) s = Slot();
    inSession = false; fired = false; moved = false; maxFingers = 0; pinchBase = 0; cur = 0;
    pinched = false; dragRef = false; dragging = false; gapMode = 0; gapDrag = false; gapProbed = false;
}

// ---- window hit test: which floating window are both fingers on? (reads mmsg JSON) ----
static std::string capture(const std::string& cmd) {
    std::string out;
    FILE* f = popen(("timeout 0.3 " + cmd).c_str(), "r");   // never let a stuck mmsg freeze the event loop
    if (!f) return out;
    char buf[4096]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0 && out.size() < (4u << 20)) out.append(buf, n);
    pclose(f);
    return out;
}
static bool getNum(const std::string& o, const char* key, double& v) {
    std::string k = std::string("\"") + key + "\":";
    size_t p = o.find(k);
    if (p == std::string::npos) return false;
    v = atof(o.c_str() + p + k.size());
    return true;
}
static bool getTrue(const std::string& o, const char* key) {
    std::string k = std::string("\"") + key + "\":true";
    return o.find(k) != std::string::npos;
}

static int hitTest(bool floatingOnly, const double* dxs, const double* dys, int need, bool inclFs) {   // returns client id, or -1
    const char* mn = env("TOUCH_MON"); std::string mon = mn ? mn : "eDP-1";
    std::string m = capture("mmsg get monitor " + mon + " 2>/dev/null");
    double monX = 0, monY = 0, monW = pxW, monH = pxH;
    getNum(m, "x", monX); getNum(m, "y", monY); getNum(m, "width", monW); getNum(m, "height", monH);
    pxW = monW; pxH = monH;
    if (monH > monW) return -1;   // rotated screen: touch axes no longer match the output
    double px[5], py[5]; int k = 0;
    if (dxs) {
        for (int i = 0; i < need; i++) {
            px[i] = (dxs[i] - minX) * monW / rangeX + monX;
            py[i] = (dys[i] - minY) * monH / rangeY + monY;
            k++;
        }
    } else {
        for (auto& s : slots) if (s.down && k < need) {
            px[k] = (s.x - minX) * monW / rangeX + monX;
            py[k] = (s.y - minY) * monH / rangeY + monY;
            k++;
        }
    }
    if (k != need) return -1;
    std::string all = capture("mmsg get all-clients 2>/dev/null");
    const std::string mark = "{\"id\":";
    int best = -1; double bestArea = 0; bool bestFocused = false, bestFloat = false, bestFs = false;
    for (size_t p = all.find(mark); p != std::string::npos; ) {
        size_t q = all.find(mark, p + 1);
        std::string o = all.substr(p, q == std::string::npos ? std::string::npos : q - p);
        p = q;
        bool fl = getTrue(o, "is_floating");
        if ((floatingOnly && !fl) || !getTrue(o, "is_visible") || (!inclFs && getTrue(o, "is_fullscreen"))) continue;
        bool isFs = getTrue(o, "is_fullscreen");
        if (o.find("\"monitor\":\"" + mon + "\"") == std::string::npos) continue;
        double id, x, y, w, h;
        if (!getNum(o, "id", id) || !getNum(o, "x", x) || !getNum(o, "y", y) ||
            !getNum(o, "width", w) || !getNum(o, "height", h)) continue;
        bool in = true;
        for (int i = 0; i < need; i++) if (px[i] < x || px[i] > x + w || py[i] < y || py[i] > y + h) in = false;
        if (!in) continue;
        bool foc = getTrue(o, "is_focused");
        double area = w * h;
        if (isFs && !bestFs) best = -1;   // a fullscreen tile beats everything under it
        else if (!isFs && bestFs) continue;
        bool better = best < 0 || (fl && !bestFloat) ||
                      (fl == bestFloat && ((foc && !bestFocused) || (foc == bestFocused && area < bestArea)));
        if (better) { best = (int)id; bestArea = area; bestFocused = foc; bestFloat = fl; bestFs = isFs; }
    }
    return best;
}

static void spawnMove(int dx, int dy, int id) {
    char arg[48], cl[24];
    snprintf(arg, sizeof arg, "movewin,%+d,%+d", dx, dy);   // explicit sign = relative move
    snprintf(cl, sizeof cl, "client,%d", id);
    pid_t p = fork();
    if (p == 0) {
        setsid();
        signal(SIGCHLD, SIG_DFL);
        execlp("mmsg", "mmsg", "dispatch", arg, cl, (char*)nullptr);
        _exit(127);
    }
}

static void dragStep(int n) {
    if (n != DRAG_FINGERS || maxFingers != DRAG_FINGERS || pinched) { dragRef = false; dragging = false; return; }
    double cx = 0, cy = 0; int k = 0;
    for (auto& s : slots) if (s.down) { cx += s.x; cy += s.y; k++; }
    if (k != DRAG_FINGERS) return;
    cx /= k; cy /= k;
    if (!dragRef) {   // both fingers just landed: only drag if both are on one floating window
        refX = cx; refY = cy; dragRef = true; accX = accY = 0;
        dragTarget = hitTest(true, nullptr, nullptr, DRAG_FINGERS);
        kbShown = dragTarget >= 0 && capture("mmsg get all-layers 2>/dev/null").find("\"name\":\"wvkbd\"") != std::string::npos;
        return;
    }
    if (dragTarget < 0) return;
    if (!dragging) {
        if (std::hypot(cx - refX, cy - refY) <= DRAG_DEAD * diag) return;
        // Keyboard showing and the slide goes mostly DOWN: that is "hide keyboard", not a window drag.
        if (kbShown && cy - refY > 0 && std::fabs(cy - refY) > std::fabs(cx - refX)) { dragTarget = -1; return; }
        dragging = true; fired = true;   // fired: no swipe / tap / long-press for this gesture
    }
    accX += (cx - refX) * pxW / rangeX;  accY += (cy - refY) * pxH / rangeY;
    refX = cx; refY = cy;
    auto now = Clock::now();
    if (std::chrono::duration_cast<std::chrono::milliseconds>(now - lastEmit).count() < EMIT_MS) return;
    int ix = (int)accX, iy = (int)accY;
    if (!ix && !iy) return;
    spawnMove(ix, iy, dragTarget);
    accX -= ix; accY -= iy; lastEmit = now;
}

// ---- grab the gap between tiles with 1 finger and drag: resizes the tiles ----
struct Rect { int id; double x, y, w, h; bool floating; };

static std::vector<Rect> listClients(const std::string& mon) {
    std::vector<Rect> v;
    std::string all = capture("mmsg get all-clients 2>/dev/null");
    const std::string mark = "{\"id\":";
    for (size_t p = all.find(mark); p != std::string::npos; ) {
        size_t q = all.find(mark, p + 1);
        std::string o = all.substr(p, q == std::string::npos ? std::string::npos : q - p);
        p = q;
        if (!getTrue(o, "is_visible") || getTrue(o, "is_fullscreen")) continue;
        if (o.find("\"monitor\":\"" + mon + "\"") == std::string::npos) continue;
        double id, x, y, w, h;
        if (!getNum(o, "id", id) || !getNum(o, "x", x) || !getNum(o, "y", y) ||
            !getNum(o, "width", w) || !getNum(o, "height", h)) continue;
        v.push_back({(int)id, x, y, w, h, getTrue(o, "is_floating")});
    }
    return v;
}

// Called once when the first finger lands. Sets gapMode/gapTarget if the finger is on a gap between two tiles.
static void gapProbe() {
    gapMode = 0; gapTarget = -1; gapDrag = false;
    const char* mn = env("TOUCH_MON"); std::string mon = mn ? mn : "eDP-1";
    std::string m = capture("mmsg get monitor " + mon + " 2>/dev/null");
    double monX = 0, monY = 0, monW = pxW, monH = pxH;
    getNum(m, "x", monX); getNum(m, "y", monY); getNum(m, "width", monW); getNum(m, "height", monH);
    pxW = monW; pxH = monH;
    if (monH > monW) return;   // rotated screen: touch axes no longer match, skip gap grab
    double X = (fx - minX) * monW / rangeX + monX, Y = (fy - minY) * monH / rangeY + monY;
    std::vector<Rect> cl = listClients(mon);
    for (auto& c : cl) if (c.floating && X >= c.x && X <= c.x + c.w && Y >= c.y && Y <= c.y + c.h) return;
    double bestD = 1e9;
    for (auto& a : cl) for (auto& b : cl) {
        if (a.floating || b.floating || a.id == b.id) continue;
        double gv = b.x - (a.x + a.w), gh = b.y - (a.y + a.h);   // a left of b / a above b
        if (gv >= -2 && gv <= GAP_MAX && X >= a.x + a.w - GAP_TOL && X <= b.x + GAP_TOL &&
            Y >= a.y && Y <= a.y + a.h && Y >= b.y && Y <= b.y + b.h) {
            double d = std::fabs(X - (a.x + a.w + gv / 2));
            if (d < bestD) { bestD = d; gapMode = 'V'; gapTarget = a.id; }
        }
        if (gh >= -2 && gh <= GAP_MAX && Y >= a.y + a.h - GAP_TOL && Y <= b.y + GAP_TOL &&
            X >= a.x && X <= a.x + a.w && X >= b.x && X <= b.x + b.w) {
            double d = std::fabs(Y - (a.y + a.h + gh / 2));
            if (d < bestD) { bestD = d; gapMode = 'H'; gapTarget = a.id; }
        }
    }
    if (gapMode) fprintf(stderr, "gap grab: %c target client %d\n", gapMode, gapTarget);
}

static void spawnResize(int d, bool horizontalAxis, int id) {
    char arg[48], cl[24];
    if (horizontalAxis) snprintf(arg, sizeof arg, "resizewin,%+d,+0", d);
    else snprintf(arg, sizeof arg, "resizewin,+0,%+d", d);
    snprintf(cl, sizeof cl, "client,%d", id);
    pid_t p = fork();
    if (p == 0) {
        setsid();
        signal(SIGCHLD, SIG_DFL);
        execlp("mmsg", "mmsg", "dispatch", arg, cl, (char*)nullptr);
        _exit(127);
    }
}

static void gapStep(int n) {
    if (n != 1 || maxFingers != 1) { gapMode = 0; gapDrag = false; return; }   // another finger joined: cancel
    if (fired && !gapDrag) return;                                             // long-press already fired
    const Slot* s = nullptr;
    for (auto& q : slots) if (q.down) { s = &q; break; }
    if (!s) return;
    if (!gapProbed) {   // look for a gap only once the finger has really moved (taps never pay for it)
        if (std::hypot(s->x - fx, s->y - fy) * std::min(pxW / rangeX, pxH / rangeY) < GAP_DEAD_PX) return;
        gapProbed = true;
        gapProbe();
    }
    if (!gapMode) return;
    bool V = gapMode == 'V';
    double cur = V ? s->x : s->y, scale = V ? pxW / rangeX : pxH / rangeY;
    if (!gapDrag) {
        double start = V ? fx : fy;
        if (std::fabs(cur - start) * scale < GAP_DEAD_PX) return;
        gapDrag = true; fired = true; gapRef = start; gapAcc = 0;
    }
    gapAcc += (cur - gapRef) * scale; gapRef = cur;
    auto now = Clock::now();
    if (std::chrono::duration_cast<std::chrono::milliseconds>(now - gapLast).count() < EMIT_MS) return;
    int d = (int)gapAcc;
    if (!d) return;
    spawnResize(d, V, gapTarget);
    gapAcc -= d; gapLast = now;
}

static void afterSync() {
    int n = fingers();
    if (n > 0 && !inSession) { inSession = true; t0 = Clock::now(); maxFingers = 0; moved = false; fired = false; }
    if (n > 0 && maxFingers == 0) {   // first finger of the session: remember where it landed (edge test)
        for (auto& s : slots) if (s.down) { fx = s.x; fy = s.y; break; }
    }
    if (n > maxFingers) {             // new peak finger count: start point of the swipe
        double cx = 0, cy = 0;
        for (auto& s : slots) if (s.down) { cx += s.x; cy += s.y; }
        stCx = cx / n; stCy = cy / n;
    }
    if (n > maxFingers) maxFingers = n;
    if (n == maxFingers && n > 0) {   // end point: last centroid with all fingers still down
        double cx = 0, cy = 0;
        for (auto& s : slots) if (s.down) { cx += s.x; cy += s.y; }
        enCx = cx / n; enCy = cy / n;
    }
    if (inSession && n == 0) { endSession(); return; }
    if (!inSession) return;

    // Moving fingers cancel tap/long-press. Pinch is judged separately below.
    checkMoved();

    if (n == 2 && maxFingers == 2 && !dragging) {
        double d = pinchDist();
        if (pinchBase == 0) pinchBase = d;
        else if (pinchBase > 0) {
            double r = d / pinchBase;
            if (r > 1 + PINCH_STEP) { run("CMD_PINCH_OUT"); pinchBase = d; fired = true; pinched = true; }
            else if (r < 1 - PINCH_STEP) { run("CMD_PINCH_IN"); pinchBase = d; fired = true; pinched = true; }
        }
    } else if (n != 2) {
        pinchBase = 0;
    }
    dragStep(n);
    gapStep(n);
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: tapd /dev/input/eventN\n"); return 2; }
    signal(SIGCHLD, SIG_IGN);
    setvbuf(stderr, nullptr, _IOLBF, 0);
    int fd = open(argv[1], O_RDONLY | O_CLOEXEC);
    if (fd < 0) { perror("open"); return 1; }

    input_absinfo ax{}, ay{};
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ax) == 0 && ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ay) == 0)
        diag = std::hypot(ax.maximum - ax.minimum, ay.maximum - ay.minimum);
    if (diag < 1) diag = 1000;
    rangeX = std::max(1, ax.maximum - ax.minimum); rangeY = std::max(1, ay.maximum - ay.minimum);
    minX = ax.minimum; minY = ay.minimum;
    if (env("PX_W")) pxW = atof(env("PX_W"));
    if (env("PX_H")) pxH = atof(env("PX_H"));

    pollfd pfd{fd, POLLIN, 0};
    for (;;) {
        // Wake up in time for the long-press check while exactly one finger is held.
        int timeout = -1;
        if (inSession && !fired && !moved && fingers() == maxFingers && (maxFingers == 1 || maxFingers == 2)) {
            long left = LONG_MS - msSince();
            timeout = left > 0 ? (int)left : 0;
        }
        int pr = poll(&pfd, 1, timeout);
        if (pr < 0) { if (errno == EINTR) continue; perror("poll"); return 1; }
        if (pr == 0) { checkLong(); continue; }
        input_event ev;
        ssize_t n = read(fd, &ev, sizeof ev);
        if (n != (ssize_t)sizeof ev) { if (n < 0 && errno == EINTR) continue; return 1; }
        if (dropping) {                       // buffer overflowed: ignore until the next SYN_REPORT
            if (ev.type == EV_SYN && ev.code == SYN_REPORT) dropping = false;
            continue;
        }
        if (ev.type == EV_SYN && ev.code == SYN_DROPPED) { resetAll(); dropping = true; continue; }
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_SLOT) { cur = (ev.value >= 0 && ev.value < MAXSLOT) ? ev.value : -1; continue; }
            if (cur < 0) continue;            // slot out of range: ignore its events
            switch (ev.code) {
            case ABS_MT_TRACKING_ID:
                if (ev.value < 0) slots[cur].down = false;
                else { slots[cur].down = true; slots[cur].sx = slots[cur].sy = -1; }
                break;
            case ABS_MT_POSITION_X:
                slots[cur].x = ev.value; if (slots[cur].sx == -1) slots[cur].sx = ev.value; break;
            case ABS_MT_POSITION_Y:
                slots[cur].y = ev.value; if (slots[cur].sy == -1) slots[cur].sy = ev.value; break;
            }
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            afterSync();
            checkLong();                      // jitter events keep poll awake, so check here too
        }
    }
}
