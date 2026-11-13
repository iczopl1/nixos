/*
 * wpm-global – globalny licznik WPM z /dev/input, ustawia kolor obramówki w Mango.
 * Blokuje na select() z 300 ms timeout – praktycznie 0% CPU w spoczynku.
 * Wymaga grupy `input` (dostęp do /dev/input/event*).
 *
 * Kompilacja: cc -O2 -o wpm-global wpm-global.c
 * Użycie: wpm-global [--wpm-file /tmp/nvim-wpm-1000]
 */
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <linux/input.h>

/* ── konfiguracja ───────────────────────────────────────────────── */
#define WINDOW_S        5       /* okno rolling (s) */
#define CHARS_PER_WORD  5
#define REFRESH_MS      300     /* co ile ms odświeżamy kolor */
#define MAX_DEVS        16
#define MAX_TS          512     /* max znaczników w oknie */
#define IDLE_RESET_S    3       /* po ilu sekundach bez pisania wróć do default */

/* ── kolory (gradient błękit→bursztyn→czerwień) ─────────────────── */
static const char *DEFAULT_COLOR = "0x9eeaf9ff";

typedef struct { int wpm; unsigned char r, g, b; } Stop;
static const Stop STOPS[] = {
    {  0, 0x1e, 0x1e, 0x2e },
    { 20, 0x9e, 0xea, 0xf9 },
    { 50, 0xe0, 0xaf, 0x68 },
    { 90, 0xf7, 0x76, 0x8e },
};
#define NSTOPS (int)(sizeof(STOPS)/sizeof(STOPS[0]))

static int lerp(int a, int b, double t) {
    if (t < 0) t = 0; if (t > 1) t = 1;
    return (int)(a + (b - a) * t);
}

static void wpm_to_color(int wpm, char out[16]) {
    for (int i = 1; i < NSTOPS; i++) {
        if (wpm <= STOPS[i].wpm) {
            double t = (double)(wpm - STOPS[i-1].wpm) /
                       (STOPS[i].wpm - STOPS[i-1].wpm);
            snprintf(out, 16, "0x%02x%02x%02xff",
                lerp(STOPS[i-1].r, STOPS[i].r, t),
                lerp(STOPS[i-1].g, STOPS[i].g, t),
                lerp(STOPS[i-1].b, STOPS[i].b, t));
            return;
        }
    }
    snprintf(out, 16, "0x%02x%02x%02xff",
        STOPS[NSTOPS-1].r, STOPS[NSTOPS-1].g, STOPS[NSTOPS-1].b);
}

/* ── timestampy naciśnięć ───────────────────────────────────────── */
static double ts[MAX_TS];
static int ts_head = 0, ts_count = 0;

static void ts_push(double t) {
    ts[(ts_head + ts_count) % MAX_TS] = t;
    if (ts_count < MAX_TS) ts_count++;
    else ts_head = (ts_head + 1) % MAX_TS;
}

static double now_s(void) {
    struct timespec tp;
    clock_gettime(CLOCK_MONOTONIC, &tp);
    return tp.tv_sec + tp.tv_nsec * 1e-9;
}

static int calc_wpm(void) {
    double now = now_s();
    double cutoff = now - WINDOW_S;
    /* wyrzuć stare */
    while (ts_count > 0 && ts[ts_head] < cutoff) {
        ts_head = (ts_head + 1) % MAX_TS;
        ts_count--;
    }
    if (ts_count < 2) return 0;
    double elapsed = now - ts[ts_head];
    if (elapsed < 0.1) return 0;
    return (int)((ts_count / (double)CHARS_PER_WORD) / (elapsed / 60.0));
}

/* ── klawisze ignorowane (modyfikatory, F-klawisze, nav) ────────── */
static int ignore_key(int code) {
    /* Shift, Ctrl, Alt, Meta, CapsLock */
    if (code == KEY_LEFTSHIFT  || code == KEY_RIGHTSHIFT) return 1;
    if (code == KEY_LEFTCTRL   || code == KEY_RIGHTCTRL)  return 1;
    if (code == KEY_LEFTALT    || code == KEY_RIGHTALT)   return 1;
    if (code == KEY_LEFTMETA   || code == KEY_RIGHTMETA)  return 1;
    if (code == KEY_CAPSLOCK   || code == KEY_NUMLOCK)    return 1;
    /* F1-F12 */
    if (code >= KEY_F1 && code <= KEY_F12) return 1;
    /* nawigacja */
    if (code == KEY_UP || code == KEY_DOWN ||
        code == KEY_LEFT || code == KEY_RIGHT) return 1;
    if (code == KEY_HOME || code == KEY_END ||
        code == KEY_PAGEUP || code == KEY_PAGEDOWN) return 1;
    if (code == KEY_INSERT || code == KEY_DELETE) return 1;
    if (code == KEY_ESC) return 1;
    return 0;
}

/* ── otwieranie klawiatur z /dev/input ──────────────────────────── */
static int open_keyboards(int fds[MAX_DEVS]) {
    int n = 0;
    DIR *d = opendir("/dev/input");
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d)) && n < MAX_DEVS) {
        if (strncmp(e->d_name, "event", 5)) continue;
        char path[64];
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);

        /* Sprawdź nazwę urządzenia */
        char name_path[128];
        snprintf(name_path, sizeof(name_path),
                 "/sys/class/input/%s/device/name", e->d_name);
        FILE *nf = fopen(name_path, "r");
        if (!nf) continue;
        char name[128] = {0};
        fgets(name, sizeof(name), nf);
        fclose(nf);
        /* zamień na lowercase */
        for (char *p = name; *p; p++) if (*p >= 'A' && *p <= 'Z') *p += 32;

        /* pomiń nie-klawiatury */
        if (strstr(name, "mouse"))      continue;
        if (strstr(name, "touchpad"))   continue;
        if (strstr(name, "trackpoint")) continue;
        if (strstr(name, "headphone"))  continue;
        if (strstr(name, "mic"))        continue;
        if (strstr(name, "pcbeep"))     continue;
        if (strstr(name, "video"))      continue;
        if (strstr(name, "tablet"))     continue;
        if (strstr(name, "pen"))        continue;
        if (strstr(name, "ydotoold"))   continue;
        if (strstr(name, "keyd virtual")) continue;

        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        /* Sprawdź czy urządzenie ma klawisze (EV_KEY bit) */
        unsigned long evbit = 0;
        if (ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), &evbit) < 0 ||
            !(evbit & (1 << EV_KEY))) {
            close(fd);
            continue;
        }
        fds[n++] = fd;
    }
    closedir(d);
    return n;
}

/* ── mmsg + WPM plik ────────────────────────────────────────────── */
static void set_color(const char *color) {
    char cmd[128];
    snprintf(cmd, sizeof(cmd),
             "mmsg dispatch setoption,focus_color,%s 2>/dev/null", color);
    system(cmd);
}

static void write_wpm_file(const char *path, int wpm) {
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%d", wpm); fclose(f); }
}

/* ─────────────────────────────────────────────────────────────────── */
int main(int argc, char **argv) {
    const char *wpm_file = NULL;
    for (int i = 1; i < argc - 1; i++) {
        if (!strcmp(argv[i], "--wpm-file")) wpm_file = argv[i+1];
    }
    if (!wpm_file) {
        /* domyślna ścieżka zgodna z typing_speed.lua */
        static char buf[64];
        snprintf(buf, sizeof(buf), "/tmp/nvim-wpm-%d", (int)getuid());
        wpm_file = buf;
    }

    int fds[MAX_DEVS];
    int nfds = open_keyboards(fds);
    if (nfds == 0) {
        fprintf(stderr, "wpm-global: nie znaleziono klawiatur w /dev/input\n");
        return 1;
    }

    char cur_color[16];
    strncpy(cur_color, DEFAULT_COLOR, sizeof(cur_color));
    double last_keypress = 0;

    for (;;) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = -1;
        for (int i = 0; i < nfds; i++) {
            FD_SET(fds[i], &rfds);
            if (fds[i] > maxfd) maxfd = fds[i];
        }

        struct timeval tv = { .tv_sec = 0, .tv_usec = REFRESH_MS * 1000 };
        int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);

        if (ret > 0) {
            /* Odczytaj eventy */
            for (int i = 0; i < nfds; i++) {
                if (!FD_ISSET(fds[i], &rfds)) continue;
                struct input_event ev;
                while (read(fds[i], &ev, sizeof(ev)) == sizeof(ev)) {
                    if (ev.type == EV_KEY && ev.value == 1 &&
                        !ignore_key(ev.code)) {
                        double t = now_s();
                        ts_push(t);
                        last_keypress = t;
                    }
                }
            }
        }

        /* Odśwież kolor co REFRESH_MS (niezależnie od eventów) */
        int wpm = calc_wpm();
        write_wpm_file(wpm_file, wpm);

        char new_color[16];
        double idle = now_s() - last_keypress;
        if (wpm > 0) {
            wpm_to_color(wpm, new_color);
        } else if (idle >= IDLE_RESET_S) {
            strncpy(new_color, DEFAULT_COLOR, sizeof(new_color));
        } else {
            strncpy(new_color, cur_color, sizeof(new_color));
        }

        if (strcmp(new_color, cur_color)) {
            set_color(new_color);
            strncpy(cur_color, new_color, sizeof(cur_color));
        }
    }
}
