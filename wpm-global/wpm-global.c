/*
 * wpm-global – globalny licznik WPM z /dev/input, zapisuje do pliku dla nvim (typing_speed.lua,
 * T3.5 – licznik w lualine). Blokuje na select() z 300 ms timeout – praktycznie 0% CPU w spoczynku.
 * Wymaga grupy `input` (dostęp do /dev/input/event*).
 *
 * NIE ustawia koloru obramówki (focus_color) – to robi WpmBorder.qml (Quickshell), z własnymi
 * togglami `effects wpm-color`/`wpm-move`/`wpm-count`. Oba programy ustawiające focus_color
 * naraz = użytkownik nie ma kontroli przez effects-ctl.sh (patrz BROKEN.md/git log 2026-11-14).
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
#define REFRESH_MS      300     /* co ile ms odświeżamy plik WPM */
#define MAX_DEVS        16
#define MAX_TS          512     /* max znaczników w oknie */

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

/* ── WPM plik (dla typing_speed.lua w nvim) ─────────────────────── */
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
                        ts_push(now_s());
                    }
                }
            }
        }

        /* Odśwież plik co REFRESH_MS (niezależnie od eventów) */
        write_wpm_file(wpm_file, calc_wpm());
    }
}
