# Komendy

## Konfiguracja systemu

W repozytorium używaj skryptu `rebuild.sh`:

| Komenda | Działanie |
|---|---|
| `./rebuild.sh -n "opis"` | kontrola konfiguracji i dry-build bez wdrażania |
| `./rebuild.sh "opis zmiany"` | build w trybie boot; po sukcesie commit i kopia do `/etc/nixos` |
| `./auto.sh` | przygotowanie nowej maszyny i profilu |
| `./make-zip.sh` | przygotowanie archiwum rdzenia konfiguracji |
| `rebuild` / `rebuild-dry` | aliasy do `rebuild.sh` z bieżącej lokalizacji repozytorium |
| `update-boot` | ręczne `nixos-rebuild boot` z aktywną konfiguracją |

Agent nie używa `switch`. Po poprawnym buildzie uruchom system ponownie, aby
załadować nową generację. Pełna procedura jest w [SETUP.md](../SETUP.md).

## Mango i Quickshell

```bash
mango -c ~/.config/mango/config.conf -p  # sprawdzenie konfiguracji Mango
qs                                         # restart Quickshell (bar)
effects                                    # wybór efektów Mango/Quickshell (menu)
effects all off                            # szybki wyłącznik wszystkich efektów na raz
effects edit                               # edycja ~/.config/mango-effects.conf (# wyłącza)
```

Mango wysyła część zdarzeń paska przez gniazda w `$XDG_RUNTIME_DIR`; `mmsg`
i `socat` są używane przez konfigurację oraz nakładki Quickshell.

## Skróty powłoki

`shell.nix` definiuje m.in. aliasy `ls`/`ll`/`l` przez eza, `g` przez ripgrep,
`b` dla btop, `ch` dla bat, `n` dla nmtui, `s`/`gs` dla git status oraz skróty
do nawigacji (`..`, `...`, `cdd`). Funkcje interaktywne obejmują `a` (wyszukaj
i otwórz wynik w nvim), `e`/`fe`/`fo`, `d`/`h` (historia), `m`, `p`/`pk`, `py`,
`q` i `x`/`u`. `agent` pokazuje podsumowanie środowiska. Pełne definicje są w
`shell.nix`.

## Skrypty użytkownika

Skrypty są linkowane pod `~/.config/scripts/` z `dotfiles/scripts/`:

| Przykład | Działanie |
|---|---|
| `effects-ctl.sh` | konfiguruje blur, animacje, particles, pasek i efekty WPM |
| `screenrec-toggle.sh` | start/stop nagrywania ekranu do `~/Videos` |
| `throttle.sh` | ogranicza przepustowość interfejsu sieciowego |
| `syncthing-status.sh` | odczytuje stan Syncthing do paska |
| `prz-schedule.py --ics` | pobiera kalendarz zajęć PRz i zapisuje ICS |
| `phone-status.sh`, `bt-headset.sh` | stan telefonu i przełączanie słuchawek BT |
| `switch-random-wallpaper.sh` | losuje tapetę i aktualizuje motyw |
| `bgm-power-monitor.sh` | steruje muzyką zależnie od zasilania |

Nazwy i szczegóły wszystkich skryptów: [dotfiles-i-skrypty.md](dotfiles-i-skrypty.md).

## Python i G1-Prz-Controll

W profilu full `python3` to Python 3.13 z pakietami z `python.nix`; w minimal
dostępny jest podstawowy Python. Dla projektu G1 aktywuj jego `.venv` albo
uruchamiaj Nixowego Pythona z katalogu projektu:

```bash
python3 -c 'import tkinter, _tkinter, numpy, PIL, paramiko, scp, pygame'
command -v ffmpeg ffprobe pactl
python3 frontend/main_app.py
```

Venv projektu musi mieć `include-system-site-packages = true`, aby widzieć Nixowe
NumPy i Pillow. Pakiet MuJoCo jest opcjonalny; jego katalog można wskazać przez
`G1PRZ_MUJOCO_ROOT` i `G1PRZ_MUJOCO_SITE_PACKAGES`.

## Audio, sieć i urządzenia

```bash
wpctl status
wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
pactl info
tailscale status
tailscale --socket=/run/tailscale-b/tailscaled.sock status
adb devices
bluetoothctl
```

W profilu full uruchom `ros2-humble`, aby wejść do środowiska ROS 2 dla Unitree
G1. Przy połączeniu kablem Ethernet wskaż interfejs, np.
`UNITREE_ROS_INTERFACE=enp3s0 ros2-humble`; nazwa zależy od laptopa. Z katalogu
`unitree_ros2/cyclonedds_ws` zbuduj pakiety poleceniem `colcon build`, a potem
sprawdź komunikację przez `ros2 topic list`. Polecenie dołącza overlay
workspace, jeśli istnieje `install/setup.bash`. Podman/Distrobox nadal są
dostępne w profilu full. Nie wykonuj poleceń sterujących ruchem robota bez
właściwego nadzoru.
