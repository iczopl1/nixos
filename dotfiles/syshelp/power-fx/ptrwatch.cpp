// ptrwatch: tells power-fx where the cursor is and when you click. Event-driven:
// while nothing happens it sleeps in poll() with NO timeout, so it uses zero CPU.
//
// Output lines (stdout):
//   c                                   a mouse click or touchpad tap
//   s DX DY                             scrolling (wheel, or two fingers on a touchpad); only the
//                                       axis matters, the signs are whatever the device reports
//   T N U V / t N U V / tu N            touchscreen, finger N (slot 0..9): first point / later points
//                                       (0..10000 of the panel width/height) / finger lifted;
//   tc N                                a short, still touch of finger N (a tap), sent just before "tu N"
//   d / u                               a mouse button went down (first one) / all buttons are up
//   {"x":..,"y":..,"monitor":".."}      cursor position, as printed by `mmsg get cursorpos`
//                                       (only when it changed; sent while the pointer moves,
//                                       once after a focus change, and once at start)
//
// How it works: it waits for events from pointer devices (mouse, touchpad, pen). When
// the pointer moves it asks the compositor for the position (~70 times a second, only
// while moving) and stops asking 120 ms after the movement stops. A focus change
// (`mmsg watch all-devices`, so a key press too) triggers one position query, because mango can warp
// the cursor on focus.
//
// Privacy: only pointer devices are read. A device is used only if it has a left mouse
// button or a pen tool AND no typing keys at all (KEY_ESC..KEY_PAUSE, codes 1..127);
// this is checked twice: from sysfs, and again on the opened fd (ioctl) before any read.
// Keyboards are never read. From pointer devices it looks at: the left/right/middle
// buttons, BTN_TOUCH and the finger-count keys, and motion/finger/pen coordinates (for
// the tap and movement tests; the coordinates are thrown away, except fingers on a
// touchscreen, whose position is sent so the trail can follow it). Nothing is logged or
// stored (only the last position line is kept in memory to skip repeats).
// Position lines are also sent after a window focus change, so the consumer can learn
// the timing of focus changes (including keyboard-driven ones) and of pointer activity.
// That is the only information it gets besides clicks and the cursor position.
//
// Lifetime: stops when its parent (quickshell) exits. If the parent died (crash/kill) it
// also runs cursor-hide.sh off, so the real cursor comes back. A normal stop by
// quickshell (e.g. unplugging the charger) does not do that; quickshell handles it.
//
// Build: g++ -O2 -std=c++17 -o ptrwatch ptrwatch.cpp   (power-fx.sh does this for you)

#include <dirent.h>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <algorithm>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <map>
#include <string>
#include <vector>

namespace {

constexpr uint16_t EV_SYN = 0, EV_KEY = 1, EV_REL = 2, EV_ABS = 3;
constexpr uint16_t REL_HWHEEL = 6, REL_WHEEL = 8, REL_WHEEL_HI_RES = 11, REL_HWHEEL_HI_RES = 12;
constexpr uint16_t SYN_REPORT = 0, SYN_DROPPED = 3;
constexpr uint16_t BTN_LEFT = 0x110, BTN_RIGHT = 0x111, BTN_MIDDLE = 0x112, BTN_TOUCH = 0x14A;
constexpr uint16_t BTN_TOOL_PEN = 0x140;
constexpr uint16_t ABS_MT_SLOT = 0x2f, ABS_MT_X = 0x35, ABS_MT_Y = 0x36, ABS_MT_TRACKING_ID = 0x39;
constexpr uint16_t BTN_TOOL_FINGER = 0x145, BTN_TOOL_DOUBLETAP = 0x14D;
constexpr uint16_t BTN_TOOL_TRIPLETAP = 0x14E, BTN_TOOL_QUADTAP = 0x14F, BTN_TOOL_QUINTTAP = 0x148;
constexpr int KEY_TYPING_MAX = 128;  // codes 1..127 are the keyboard keys
constexpr int KEY_MAX_CODE = 0x2ff;
// EVIOCGBIT(EV_KEY, len): ask the open device which key codes it has
#define PTR_EVIOCGBIT_KEY(len) _IOC(_IOC_READ, 'E', 0x20 + 1, len)

constexpr double TAP_MAX_S = 0.22;
constexpr int TAP_MAX_MOVE = 150;       // touchpad units; bigger = a swipe, not a tap
constexpr int64_t ACTIVE_POLL_MS = 6;   // pause between position queries while moving
constexpr int64_t SETTLE_MS = 120;      // stop querying this long after the last motion
constexpr int64_t FOCUS_DELAY_MS = 80;  // let mango finish a focus warp before asking

struct InputEvent {  // 64-bit Linux struct input_event
    int64_t sec, usec;
    uint16_t type, code;
    int32_t value;
};

volatile sig_atomic_t g_term = 0;
void on_term(int) { g_term = 1; }

// TERM/INT/HUP stay blocked except inside ppoll(), so a signal can never slip in between
// "check g_term" and "go to sleep" (that would sleep forever, with no timeout).
sigset_t g_orig_mask;

// Run in a forked child before exec: undo what we changed for ourselves. While the stop
// signals are still blocked, put their handlers back to default (so the copy of our
// handler can never run in the child); optionally die with the parent, and quit at once
// if the parent is already gone; unblock last.
void child_reset(bool die_with_parent, pid_t parent) {
    signal(SIGPIPE, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    if (die_with_parent) {
        prctl(PR_SET_PDEATHSIG, SIGTERM);
        if (getppid() != parent) _exit(0);
    }
    sigprocmask(SIG_SETMASK, &g_orig_mask, nullptr);
}

int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch()).count();
}

double now_s() { return now_ms() / 1000.0; }

// ---- device selection ------------------------------------------------------------

// Capability files hold 64-bit hex words, highest word first.
std::vector<uint64_t> read_caps(const std::string& path) {
    std::vector<uint64_t> words;
    std::ifstream f(path);
    std::string w;
    while (f >> w) words.push_back(std::strtoull(w.c_str(), nullptr, 16));
    return words;
}

bool has_bit(const std::vector<uint64_t>& words, int bit) {
    size_t idx = bit / 64;
    if (idx >= words.size()) return false;
    return (words[words.size() - 1 - idx] >> (bit % 64)) & 1;
}

bool any_bit(const std::vector<uint64_t>& words) {
    for (auto w : words)
        if (w) return true;
    return false;
}

// True if the device has any typing key. Such a device is never used.
bool has_typing_keys(const std::vector<uint64_t>& words) {
    for (int c = 1; c < KEY_TYPING_MAX; c++)
        if (has_bit(words, c)) return true;
    return false;
}

// Same rule, but on the open fd, so it cannot be fooled by a device node that changed
// between the sysfs check and the open().
bool fd_is_pointer(int fd) {
    uint8_t bits[KEY_MAX_CODE / 8 + 1] = {};
    if (ioctl(fd, PTR_EVIOCGBIT_KEY(sizeof bits), bits) < 0) return false;
    for (int c = 1; c < KEY_TYPING_MAX; c++)
        if (bits[c / 8] >> (c % 8) & 1) return false;
    auto bit = [&](int c) { return (bits[c / 8] >> (c % 8) & 1) != 0; };
    return bit(BTN_LEFT) || bit(BTN_TOOL_PEN);
}

// Touchscreens have no mouse buttons, so fd_is_pointer() would refuse them. Same privacy
// rule on the open fd: no typing key at all.
bool fd_no_typing_keys(int fd) {
    uint8_t bits[KEY_MAX_CODE / 8 + 1] = {};
    if (ioctl(fd, PTR_EVIOCGBIT_KEY(sizeof bits), bits) < 0) return false;
    for (int c = 1; c < KEY_TYPING_MAX; c++)
        if (bits[c / 8] >> (c % 8) & 1) return false;
    return true;
}

struct AbsInfo {   // the kernel's struct input_absinfo
    int32_t value, minimum, maximum, fuzz, flat, resolution;
};

struct Dev {
    int fd = -1;
    bool touchpad = false;
    bool tracking = false;  // a single finger is down
    bool multi = false;     // 2+ fingers touched since the last full lift-off
    double t0 = 0;
    int moved = 0;
    std::map<uint16_t, int32_t> base;
    bool release = false;
    unsigned held = 0;      // bit per pressed button (left, right, middle)
    bool two = false;       // exactly two fingers on the touchpad (a scroll)
    bool hasx = false, hasy = false;
    int lastx = 0, lasty = 0;
    int accx = 0, accy = 0; // finger movement since the last "s" line
    int nfing = 0;          // fingers on the touchpad now
    int curx = 0, cury = 0;
    int xmin = 0, xmax = 0, ymin = 0, ymax = 0;   // touchpad size, to find the bottom-right button area
    // touchscreen (fingers on the screen itself): every finger (slot 0..9) is followed
    bool touchscr = false;
    int tslot = 0;          // slot the next ABS_MT event belongs to
    struct Fin {
        bool act = false, dirty = false, hx = false, hy = false, down = false, up = false;
        int x = 0, y = 0, sx = 0, sy = 0, moved = 0;   // now, first touch, biggest distance from it
        double t0 = 0;
    } fin[10];
    int txmin = 0, txmax = 0, tymin = 0, tymax = 0;   // MT position ranges
};

// Number of buttons held across all devices. "d" is printed when it goes 0 -> 1 and "u"
// when it goes back to 0, so the trail can draw a drag.
int g_held = 0;

void scan(std::map<std::string, Dev>& devs) {
    DIR* d = opendir("/sys/class/input");
    if (!d) return;
    while (dirent* e = readdir(d)) {
        std::string name = e->d_name;
        if (name.rfind("event", 0) != 0) continue;
        std::string dev = "/dev/input/" + name;
        if (devs.count(dev)) continue;
        std::string base = "/sys/class/input/" + name + "/device/capabilities/";
        auto key = read_caps(base + "key");
        if (has_typing_keys(key)) continue;
        // A touchscreen: BTN_TOUCH, multitouch X/Y, "direct" property, no pen, no mouse buttons.
        auto abs = read_caps(base + "abs");
        auto props = read_caps("/sys/class/input/" + name + "/device/properties");
        bool ts = has_bit(key, BTN_TOUCH) && !has_bit(key, BTN_LEFT) && !has_bit(key, BTN_TOOL_PEN) &&
                  has_bit(abs, ABS_MT_X) && has_bit(abs, ABS_MT_Y) && has_bit(props, 1 /* INPUT_PROP_DIRECT */);
        if (!ts && !has_bit(key, BTN_LEFT) && !has_bit(key, BTN_TOOL_PEN)) continue;  // not a pointer
        int fd = open(dev.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        if (ts ? !fd_no_typing_keys(fd) : !fd_is_pointer(fd)) {  // re-check on the real device; nothing was read yet
            close(fd);
            continue;
        }
        Dev nd;
        nd.fd = fd;
        nd.touchscr = ts;
        if (ts) {
            AbsInfo ax{}, ay{};
            if (ioctl(fd, _IOR('E', 0x40 + ABS_MT_X, AbsInfo), &ax) != 0 || ioctl(fd, _IOR('E', 0x40 + ABS_MT_Y, AbsInfo), &ay) != 0 ||
                ax.maximum <= ax.minimum || ay.maximum <= ay.minimum) {
                close(fd);
                continue;
            }
            nd.txmin = ax.minimum; nd.txmax = ax.maximum;
            nd.tymin = ay.minimum; nd.tymax = ay.maximum;
            devs[dev] = nd;
            continue;
        }
        nd.touchpad = has_bit(key, BTN_TOOL_FINGER) && any_bit(read_caps(base + "abs"));
        if (nd.touchpad) {
            AbsInfo ax{}, ay{};
            if (ioctl(fd, _IOR('E', 0x40 + 0, AbsInfo), &ax) == 0 && ioctl(fd, _IOR('E', 0x40 + 1, AbsInfo), &ay) == 0) {
                nd.xmin = ax.minimum;
                nd.xmax = ax.maximum;
                nd.ymin = ay.minimum;
                nd.ymax = ay.maximum;
            }
        }
        devs[dev] = nd;
    }
    closedir(d);
}

// ---- output ------------------------------------------------------------------------

void write_line(const std::string& s) {
    std::string l = s + "\n";
    ssize_t r = write(STDOUT_FILENO, l.data(), l.size());
    if (r < 0 && errno == EPIPE) g_term = 1;  // nobody is listening any more: stop
    // EAGAIN (stdout is non-blocking and the reader is stalled): the line is dropped on purpose
}

void set_buttons(Dev& dev, unsigned held) {
    int before = g_held;
    g_held += __builtin_popcount(held) - __builtin_popcount(dev.held);
    if (g_held < 0) g_held = 0;
    dev.held = held;
    if (before == 0 && g_held > 0) write_line("d");
    else if (before > 0 && g_held == 0) write_line("u");
}

void emit_scroll(int dx, int dy) {
    write_line("s " + std::to_string(dx) + " " + std::to_string(dy));
}

void emit_click(const char* tag = "c") {   // "c" left or tap, "cr" right, "cm" middle
    static double last = 0;
    double t = now_s();
    if (t - last < 0.03) return;
    last = t;
    write_line(tag);
}

// Run `mmsg get cursorpos` and return its one line of output ("" on failure).
std::string query_cursor() {
    int p[2];
    if (pipe2(p, O_CLOEXEC) < 0) return "";
    pid_t pid = fork();
    if (pid < 0) {
        close(p[0]);
        close(p[1]);
        return "";
    }
    if (pid == 0) {
        child_reset(false, 0);
        dup2(p[1], STDOUT_FILENO);  // dup2 clears close-on-exec on the new fd
        execlp("mmsg", "mmsg", "get", "cursorpos", static_cast<char*>(nullptr));
        _exit(127);
    }
    close(p[1]);
    std::string out;
    char buf[256];
    pollfd pf{p[0], POLLIN, 0};
    const int64_t deadline = now_ms() + 500;  // one deadline for the whole answer
    for (;;) {
        int64_t left = deadline - now_ms();
        if (left <= 0) break;
        timespec ts{static_cast<time_t>(left / 1000), static_cast<long>(left % 1000) * 1000000L};
        int r = ppoll(&pf, 1, &ts, &g_orig_mask);  // a stop signal interrupts this
        if (r <= 0) break;                         // timeout or signal: give up on this one
        ssize_t n = read(p[0], buf, sizeof buf);
        if (n <= 0) break;  // EOF: complete
        out.append(buf, static_cast<size_t>(n));
        if (out.size() > 4096) break;
    }
    close(p[0]);
    kill(pid, SIGKILL);  // harmless if it already exited; guarantees waitpid cannot hang
    while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();
    // Only forward what looks like exactly one JSON object line.
    if (out.empty() || out.size() > 256 || out.front() != '{' || out.back() != '}' ||
        out.find('\n') != std::string::npos)
        return "";
    return out;
}

std::string g_last_pos;

bool emit_pos() {   // true when the position changed
    std::string q = query_cursor();
    if (q.empty() || q == g_last_pos) return false;
    g_last_pos = q;
    write_line(q);
    return true;
}

// `mmsg watch all-devices`: it prints which kind of device (keyboard, mouse, ...) just had an event,
// never which key. Here it only means "something happened, the cursor may have been moved by the
// compositor or by a virtual pointer (hint navigation, window swap)": we look at the position once.
pid_t g_watch_pid = -1;

int spawn_focus_watch() {
    int p[2];
    if (pipe2(p, O_CLOEXEC) < 0) return -1;
    fcntl(p[0], F_SETFL, O_NONBLOCK);  // read end only; mmsg's write end stays blocking
    const pid_t parent = getpid();
    pid_t pid = fork();
    if (pid < 0) {
        close(p[0]);
        close(p[1]);
        return -1;
    }
    if (pid == 0) {
        child_reset(true, parent);  // dies with us; exits at once if we are already gone
        dup2(p[1], STDOUT_FILENO);
        execlp("mmsg", "mmsg", "watch", "all-devices", static_cast<char*>(nullptr));
        _exit(127);
    }
    close(p[1]);
    g_watch_pid = pid;
    return p[0];
}

// The watch ended (compositor restarted or crashed): reap it.
void reap_focus_watch() {
    if (g_watch_pid > 0) {
        kill(g_watch_pid, SIGKILL);
        while (waitpid(g_watch_pid, nullptr, 0) < 0 && errno == EINTR) {}
        g_watch_pid = -1;
    }
}

void restore_cursor() {
    char path[4096];
    ssize_t n = readlink("/proc/self/exe", path, sizeof path - 1);
    if (n <= 0) return;
    path[n] = 0;
    std::string dir(path);
    size_t slash = dir.rfind('/');
    if (slash == std::string::npos) return;
    dir.resize(slash);
    std::string script = dir + "/cursor-hide.sh";
    pid_t pid = fork();
    if (pid == 0) {
        child_reset(false, 0);
        int nul = open("/dev/null", O_WRONLY);  // do not hand our non-blocking stdout to the script
        if (nul >= 0) dup2(nul, STDOUT_FILENO);
        execl(script.c_str(), "cursor-hide.sh", "off", static_cast<char*>(nullptr));
        _exit(127);
    }
    if (pid > 0) {  // wait at most ~2 s, then kill it, so exiting can never hang
        for (int i = 0; i < 100; i++) {
            if (waitpid(pid, nullptr, WNOHANG) != 0) return;
            usleep(20000);
        }
        kill(pid, SIGKILL);
        waitpid(pid, nullptr, 0);
    }
}

// ---- event handling --------------------------------------------------------------
// Touchscreen: every finger is followed, by its slot number N (0..9). Prints "T N U V" (first
// point of a touch) and "t N U V" (later points): finger position as 0..10000 of the panel's
// width/height, in the panel's own orientation. "tu N" when that finger lifts. A short, still
// touch also prints "tc N" for a tap. The compositor's cursor is
// not involved, so `moved` stays false.
void handle_touch(Dev& dev, const InputEvent& ev) {
    constexpr int NF = 10;
    if (ev.type == EV_ABS) {
        if (ev.code == ABS_MT_SLOT) {
            dev.tslot = ev.value;
        } else if (dev.tslot < 0 || dev.tslot >= NF) {
            return;
        } else if (ev.code == ABS_MT_TRACKING_ID) {
            Dev::Fin& f = dev.fin[dev.tslot];
            if (ev.value >= 0 && !f.act) {
                f = Dev::Fin();
                f.act = f.down = true;
                f.t0 = now_s();
            } else if (ev.value < 0 && f.act) {
                f.act = false;
                f.up = true;
            }
        } else if ((ev.code == ABS_MT_X || ev.code == ABS_MT_Y) && dev.fin[dev.tslot].act) {
            Dev::Fin& f = dev.fin[dev.tslot];
            if (ev.code == ABS_MT_X) { f.x = ev.value; if (!f.hx) f.sx = ev.value; f.hx = true; }
            else { f.y = ev.value; if (!f.hy) f.sy = ev.value; f.hy = true; }
            f.dirty = true;
        }
    } else if (ev.type == EV_SYN && ev.code == SYN_DROPPED) {
        for (int i = 0; i < NF; i++) {   // events were lost: tell the shell every finger is up
            if (dev.fin[i].act) write_line("tu " + std::to_string(i));
            dev.fin[i] = Dev::Fin();
        }
        dev.tslot = 0;
    } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
        for (int i = 0; i < NF; i++) {
            Dev::Fin& f = dev.fin[i];
            if (f.dirty && f.hx && f.hy) {
                int dx = std::abs(f.x - f.sx) * 10000 / (dev.txmax - dev.txmin);
                int dy = std::abs(f.y - f.sy) * 10000 / (dev.tymax - dev.tymin);
                f.moved = std::max(f.moved, std::max(dx, dy));
                int u = (f.x - dev.txmin) * 10000 / (dev.txmax - dev.txmin);
                int v = (f.y - dev.tymin) * 10000 / (dev.tymax - dev.tymin);
                u = std::max(0, std::min(10000, u));
                v = std::max(0, std::min(10000, v));
                write_line(std::string(f.down ? "T " : "t ") + std::to_string(i) + " " + std::to_string(u) + " " + std::to_string(v));
                f.down = false;
            }
            f.dirty = false;
            if (f.up) {
                f.up = false;
                if (now_s() - f.t0 < TAP_MAX_S && f.moved < 300)   // short and moved under 3% of the panel: a tap
                    write_line("tc " + std::to_string(i));
                write_line("tu " + std::to_string(i));
            }
        }
    }
}

void handle(Dev& dev, const InputEvent& ev, bool& moved) {
    if (dev.touchscr) {
        handle_touch(dev, ev);
        return;
    }
    if (ev.type == EV_REL) {
        if (ev.code == REL_HWHEEL) {
            if (ev.value != 0) emit_scroll(ev.value > 0 ? 1 : -1, 0);   // the pointer did not move
        } else if (ev.code == REL_WHEEL) {
            if (ev.value != 0) emit_scroll(0, ev.value > 0 ? 1 : -1);
        } else if (ev.code != REL_WHEEL_HI_RES && ev.code != REL_HWHEEL_HI_RES) {
            moved = true;
        }
    } else if (ev.type == EV_KEY) {
        bool isBtn = ev.code == BTN_LEFT || ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE;
        if (isBtn && ev.value == 0) {
            set_buttons(dev, dev.held & ~(1u << (ev.code - BTN_LEFT)));
        } else if (isBtn && ev.value == 1) {
            set_buttons(dev, dev.held | (1u << (ev.code - BTN_LEFT)));
            if (dev.touchpad) dev.tracking = false;  // a physical click is not also a tap
            {
                const char* tag = ev.code == BTN_RIGHT ? "cr" : ev.code == BTN_MIDDLE ? "cm" : "c";
                if (dev.touchpad && ev.code == BTN_LEFT) {   // a clickpad only has one button: work out which one the user meant
                    if (dev.nfing == 2) tag = "cr";
                    else if (dev.nfing >= 3) tag = "cm";
                    else if (dev.ymax > dev.ymin && dev.cury > dev.ymin + (dev.ymax - dev.ymin) * 7 / 10
                             && dev.curx > dev.xmin + (dev.xmax - dev.xmin) / 2) tag = "cr";
                }
                emit_click(tag);
            }
        } else if (dev.touchpad) {
            {   // how many fingers are on the pad (a finger count of 2 or 3 at click time means right or middle)
                int fc = ev.code == BTN_TOOL_FINGER ? 1 : ev.code == BTN_TOOL_DOUBLETAP ? 2 : ev.code == BTN_TOOL_TRIPLETAP ? 3
                       : ev.code == BTN_TOOL_QUADTAP ? 4 : ev.code == BTN_TOOL_QUINTTAP ? 5 : 0;
                if (fc > 0 && ev.value == 1) dev.nfing = fc;
                else if (fc > 0 && ev.value == 0 && dev.nfing == fc) dev.nfing = 0;
            }
            if (ev.code == BTN_TOOL_FINGER) {
                if (ev.value == 1) {
                    // Only a fresh single touch can be a tap; going 2 fingers -> 1 is not.
                    dev.tracking = !dev.multi;
                    dev.t0 = now_s();
                    dev.moved = 0;
                    dev.base.clear();
                } else if (ev.value == 0) {
                    dev.release = true;
                }
            } else if ((ev.code == BTN_TOOL_DOUBLETAP || ev.code == BTN_TOOL_TRIPLETAP ||
                        ev.code == BTN_TOOL_QUADTAP || ev.code == BTN_TOOL_QUINTTAP) && ev.value == 1) {
                dev.multi = true;
                dev.tracking = false;  // more than one finger: not a tap
                dev.two = (ev.code == BTN_TOOL_DOUBLETAP);
                dev.hasx = dev.hasy = false;
                dev.accx = dev.accy = 0;
            } else if (ev.code == BTN_TOOL_DOUBLETAP && ev.value == 0) {
                dev.two = false;
                dev.hasx = dev.hasy = false;
                dev.accx = dev.accy = 0;
            } else if (ev.code == BTN_TOUCH && ev.value == 0) {
                dev.multi = false;  // all fingers lifted
                dev.two = false;
            }
        }
    } else if (ev.type == EV_ABS && (ev.code == 0 || ev.code == 1 || ev.code == 53 || ev.code == 54)) {
        moved = true;
        if (ev.code == 0 || ev.code == 53) dev.curx = ev.value;
        if (ev.code == 1 || ev.code == 54) dev.cury = ev.value;
        if (dev.touchpad && dev.two && (ev.code == 0 || ev.code == 1)) {
            int& last = (ev.code == 0) ? dev.lastx : dev.lasty;
            bool& has = (ev.code == 0) ? dev.hasx : dev.hasy;
            int& acc = (ev.code == 0) ? dev.accx : dev.accy;
            if (has) {
                int d = ev.value - last;
                if (std::abs(d) < 400) acc += d;   // a big jump is a finger swap, not a move
            }
            last = ev.value;
            has = true;
        }
        if (dev.touchpad) {
            auto it = dev.base.find(ev.code);
            if (it == dev.base.end()) {
                dev.base[ev.code] = ev.value;
            } else {
                int m = std::abs(ev.value - it->second);
                if (m > dev.moved) dev.moved = m;
            }
        }
    } else if (ev.type == EV_SYN && ev.code == SYN_DROPPED) {
        // events were lost: our state is stale, forget it
        set_buttons(dev, 0);
        dev.tracking = false;
        dev.release = false;
        dev.multi = false;
        dev.two = false;
        dev.hasx = dev.hasy = false;
        dev.accx = dev.accy = 0;
    } else if (ev.type == EV_SYN && ev.code == SYN_REPORT && dev.release) {
        dev.release = false;
        if (dev.tracking && now_s() - dev.t0 < TAP_MAX_S && dev.moved < TAP_MAX_MOVE) emit_click();
        dev.tracking = false;
    }
    // Two-finger scroll: report the finger movement at most 60 times a second.
    if (ev.type == EV_SYN && ev.code == SYN_REPORT && dev.touchpad && dev.two &&
        (std::abs(dev.accx) + std::abs(dev.accy) >= 3)) {
        static double last_s = 0;
        double t = now_s();
        if (t - last_s >= 0.016) {
            last_s = t;
            emit_scroll(dev.accx, dev.accy);
            dev.accx = dev.accy = 0;
        }
    }
}

void drain(int fd, bool& eof, bool* keyboard = nullptr, bool* virt = nullptr) {
    char buf[512];
    for (;;) {
        ssize_t n = read(fd, buf, sizeof buf - 1);
        if (n > 0) {
            buf[n] = 0;
            if (keyboard && strstr(buf, "keyboard")) *keyboard = true;   // only the device kind is looked at
            if (virt && strstr(buf, "virtual device")) *virt = true;   // ydotool: the keyboard cursor control
            continue;
        }
        if (n == 0) eof = true;
        return;  // EAGAIN or error
    }
}

}  // namespace

int main() {
    // Die with the parent (quickshell). Read the parent pid BEFORE prctl, then check it is
    // still the same: that catches a parent that died in between (even under a subreaper).
    const pid_t ppid = getppid();
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (ppid == 1 || getppid() != ppid) return 0;
    signal(SIGPIPE, SIG_IGN);  // a closed stdout shows up as EPIPE in write_line()
    // Never block on a stalled reader: a full pipe drops lines instead of hanging us.
    fcntl(STDOUT_FILENO, F_SETFL, fcntl(STDOUT_FILENO, F_GETFL) | O_NONBLOCK);
    struct sigaction sa = {};
    sa.sa_handler = on_term;  // no SA_RESTART: a signal interrupts ppoll()
    sigaction(SIGTERM, &sa, nullptr);
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGHUP, &sa, nullptr);
    sigset_t block;
    sigemptyset(&block);
    sigaddset(&block, SIGTERM);
    sigaddset(&block, SIGINT);
    sigaddset(&block, SIGHUP);
    sigprocmask(SIG_BLOCK, &block, &g_orig_mask);  // only ppoll() lets them through

    std::map<std::string, Dev> devs;
    scan(devs);

    int ino = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);  // new devices appear in /dev/input
    if (ino >= 0 && inotify_add_watch(ino, "/dev/input", IN_CREATE | IN_ATTRIB | IN_DELETE) < 0) {
        close(ino);
        ino = -1;
    }
    int wfd = spawn_focus_watch();

    emit_pos();

    bool active = false;
    bool follow = false;   // the cursor moves without a pointer device we read (keyboard cursor control): keep looking while it changes
    int64_t last_motion = 0, last_kb = 0, wake_at = 0, key_at = 0, key2_at = 0, rescan_at = 0, respawn_at = 0;
    if (wfd < 0) respawn_at = now_ms() + 10000;  // the first start failed: try again later

    while (!g_term) {
        std::vector<pollfd> fds;
        std::vector<std::string> names;  // names[i] belongs to fds[i + 2]
        fds.push_back({ino, POLLIN, 0});
        fds.push_back({wfd, POLLIN, 0});  // a negative fd is ignored by poll()
        for (auto& [name, dev] : devs) {
            fds.push_back({dev.fd, POLLIN, 0});
            names.push_back(name);
        }

        int64_t now = now_ms();
        int timeout = -1;  // idle: sleep until something happens
        if (active) timeout = static_cast<int>(ACTIVE_POLL_MS);
        for (int64_t at : {wake_at, key_at, key2_at, rescan_at, respawn_at}) {
            if (!at) continue;
            int w = static_cast<int>(at > now ? at - now : 0);
            if (timeout < 0 || w < timeout) timeout = w;
        }

        timespec ts{};
        timespec* tsp = nullptr;  // idle: no timeout at all
        if (timeout >= 0) {
            ts.tv_sec = timeout / 1000;
            ts.tv_nsec = static_cast<long>(timeout % 1000) * 1000000L;
            tsp = &ts;
        }
        // The stop signals are unblocked only here, atomically with going to sleep.
        int r = ppoll(fds.data(), fds.size(), tsp, &g_orig_mask);
        if (r < 0) {
            if (errno == EINTR) continue;  // g_term is checked at the top
            break;
        }
        now = now_ms();

        bool eof = false;
        if (fds[0].revents & POLLIN) {
            drain(ino, eof);
            scan(devs);
            rescan_at = now + 400;  // udev sets the permissions a moment after the node appears
        }
        if (wfd >= 0 && (fds[1].revents & (POLLIN | POLLHUP))) {
            bool weof = false;
            bool kb = false, vd = false;
            drain(wfd, weof, &kb, &vd);
            if (vd) {   // the compositor saw the ydotool virtual pointer move: follow the cursor while that goes on
                last_motion = now;
                active = true;
            }
            if (kb) {
                key_at = now + 70;
                key2_at = now + 220;   // after a key press: tell the consumer to re-read the tiles
                // Keys coming fast (a held key, e.g. keyboard cursor control via ydotool) move the cursor
                // continuously, and that virtual device is not read here: follow the position while it lasts.
                if (last_kb && now - last_kb < 250) {
                    last_motion = now;
                    active = true;
                }
                last_kb = now;
            }
            if (weof) {  // mmsg ended (compositor restart?): reap it, try again later
                close(wfd);
                wfd = -1;
                reap_focus_watch();
                respawn_at = now + 5000;
            }
            wake_at = now + FOCUS_DELAY_MS;
        }

        bool moved = false;
        for (size_t i = 0; i < names.size(); i++) {
            if (!(fds[i + 2].revents & (POLLIN | POLLERR | POLLHUP))) continue;
            auto it = devs.find(names[i]);
            if (it == devs.end()) continue;
            Dev& dev = it->second;
            InputEvent buf[64];
            ssize_t n = read(dev.fd, buf, sizeof buf);
            if (n < 0) {
                if (errno == EAGAIN || errno == EINTR) continue;
                close(dev.fd);
                set_buttons(dev, 0);
                devs.erase(it);  // unplugged
                continue;
            }
            for (size_t k = 0; k < static_cast<size_t>(n) / sizeof(InputEvent); k++) handle(dev, buf[k], moved);
        }

        if (moved) {
            last_motion = now;
            active = true;
        }
        if (active) {
            bool changed = emit_pos();
            if (follow && changed) last_motion = now_ms();
            if (now_ms() - last_motion > (follow ? 300 : SETTLE_MS)) {   // that was the final position
                active = false;
                follow = false;
            }
        }
        if (wake_at && now >= wake_at) {
            wake_at = 0;
            if (emit_pos()) {   // it moved on its own: follow it while it keeps moving
                last_motion = now;
                active = true;
                follow = true;
            }
        }
        if (key_at && now >= key_at) {
            key_at = 0;
            if (emit_pos()) {   // a slow starter (ydotool) may have moved the cursor after the first look
                last_motion = now;
                active = true;
                follow = true;
            }
            write_line("k");
        }
        if (key2_at && now >= key2_at) {
            key2_at = 0;
            emit_pos();
            write_line("K");
        }
        if (rescan_at && now >= rescan_at) {
            rescan_at = 0;
            scan(devs);
        }
        if (respawn_at && now >= respawn_at) {
            respawn_at = 0;
            wfd = spawn_focus_watch();
            if (wfd < 0) respawn_at = now_ms() + 10000;  // keep trying, slowly (no wakeups while it works)
        }
    }

    // Leave stdout as we found it (it can share its open file description with a terminal).
    fcntl(STDOUT_FILENO, F_SETFL, fcntl(STDOUT_FILENO, F_GETFL) & ~O_NONBLOCK);
    // Parent died (not a normal stop by quickshell): give the real cursor back.
    if (getppid() != ppid) restore_cursor();
    return 0;
}
