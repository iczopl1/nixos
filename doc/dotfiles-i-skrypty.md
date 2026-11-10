# Dotfiles i skrypty

## Linki (`dotfiles.nix`)

Bez home-managera. Linki tworzy `systemd-tmpfiles` przy logowaniu użytkownika `iczo`.
Wskazują na folder `dotfiles/` **obok konfiguracji** (np. `/etc/nixos/dotfiles`), nie na kopię w `/nix/store`,
więc zmiany w plikach działają od razu, bez przebudowy.

| Link | Cel |
|---|---|
| `~/.config/nvim` | `dotfiles/nvim` |
| `~/.config/hypr/hyprlock.conf` | `dotfiles/hyprlock/hyprlock.conf` |
| `~/.config/rofi` | `dotfiles/rofi` |
| `~/.config/cava` | `dotfiles/cava` |
| `~/.config/waybar` | `dotfiles/waybar` |
| `~/.config/scripts` | `dotfiles/scripts` |
| `~/.ssh/config` | `dotfiles/ssh/config` |

Link powstaje tylko, gdy celu jeszcze nie ma. Jeśli np. `~/.config/nvim` już istnieje – przenieś go i zaloguj się ponownie
(albo `systemctl --user restart systemd-tmpfiles-setup`).

**Nie** zarządzane przez repo: `~/.config/mango/config.conf`, `~/.config/quickshell/`, `~/.config/wl-kbptr/config`, `~/.config/mako`.

## Tapety – `dotfiles/wallpapers/`

- Formaty: png, jpg, jpeg, webp, jxl (tylko pliki w tym folderze, bez podfolderów).
- `switch-random-wallpaper.sh` – losuje inną niż ostatnia, ustawia przez `swww` z animacją `grow` (10 s),
  potem generuje kolory `pywal` i odświeża motywy (cava-bg, `wal-apply-theme.sh`).
- `rotate-random-wallpaper.sh` – zmienia tapetę od razu, potem co godzinę (`INTERVAL`).
- Inny folder: zmienna `WALLPAPER_DIR`.
- Stan: `~/.cache/hypr-last-wallpaper`, link do aktualnej: `~/.cache/hyprlock-wallpaper` (nazwy zostały ze starych skryptów).

## Muzyka w tle – `dotfiles/bgm/`

- Formaty: mp3, flac, ogg, m4a, wav, opus (również w podfolderach).
- `bgm-power-monitor.sh` – co 5 s sprawdza zasilanie: na zasilaczu gra (mpv, głośność 50, płynne wyciszanie 3 s),
  na baterii wycisza i zatrzymuje. `toggle` = ręczne nadpisanie do następnej zmiany zasilania, `skip` = następny utwór.
  Razem z muzyką uruchamia wizualizer `launch-cava-bg.sh`.
- `bgm-current-playlist.sh` – raz dziennie (lub przy starcie odtwarzacza) tasuje playlistę → `~/.local/state/bgm/playlist.m3u`.
- Inny folder: zmienna `BGM_DIR`.

Skrypty wyliczają te foldery względem swojego prawdziwego położenia, więc działa to przez link `~/.config/scripts`
i niezależnie od tego, gdzie leży cała konfiguracja.

## Autostart

Nie ma go w NixOS – trzeba dopisać fragmenty do `~/.config/mango/config.conf`:

| Fragment | Co startuje |
|---|---|
| `mango-hintd.conf` | `hintd` (podpowiedzi SUPER+D) + skróty |
| `mango-autostart.conf` | `swww-daemon`, rotacja tapet, muzyka w tle, historia schowka (cliphist) + skróty SUPER+V/F10/F12/Insert/M |

## Pozostałe skrypty – `dotfiles/scripts/`

| Skrypt | Co robi | Wymaga |
|---|---|---|
| `wal-apply-theme.sh` | kolory z tapety (pywal) → motywy; wywołuje hyprctl tylko jeśli istnieje | pywal |
| `apply-cava-bg-theme.sh` | kolory pywal → `~/.config/cava/config-bg` | pywal |
| `launch-cava-bg.sh` | cava jako przezroczysty panel kitty w tle na `eDP-1` | kitty, cava |
| `emoji-menu.sh` | wybór emoji w rofi | rofi, wl-clipboard |
| `waybar-toggle.sh` | uruchom/zamknij waybar | waybar |
| `toggle-wvkbd.sh` + `wvkbd.conf` | klawiatura ekranowa `wvkbd-mobintl` (wysokość, czcionka, warstwy w `wvkbd.conf`) | wvkbd |

## Waybar – `dotfiles/waybar/`

- `config` (główny pasek) + `modules.json` (definicje modułów) + `style.css` / `colors.css`.
- `config-background` + `modules-background.json` + `style-background.css` – drugi wariant paska.
- Lewo: `ext/workspaces` (tagi Mango), pogoda, „now playing”, tray. Środek: zegar.
  Prawo: wireplumber, bluetooth, temperatura, GPU, CPU, pamięć, bateria, sieć.
- Pogoda (`scripts/weather.sh`): przełącza Rzeszów / Wiśniowa / Stalowa Wola.
- `custom/keyboard-layout` pokazuje na sztywno `pl` (wcześniej czytał z hyprctl).
- Kliknięcie modułu bgm → `~/.config/scripts/bgm-power-monitor.sh toggle/skip`.

Uwaga: nixos-selected używa paska **quickshell** (podpowiedzi SUPER+D są rysowane przez niego).
Waybar jest zainstalowany i skonfigurowany, ale to Ty decydujesz, który pasek startuje.

## Quickshell – `quickshell/bar/`

Pliki do skopiowania do `~/.config/quickshell/bar/` istniejącego paska:
`Hints.qml` (nakładka podpowiedzi), `HintArea.qml`, `BarTargets.qml` (singleton: przyciski paska jako cele),
`Mango.qml` (singleton: stan Mango), `holes.js`. W `shell.qml` paska dodaj `Hints {}`. Szczegóły: `../SETUP.md`.

## Inne dotfiles

| Folder | Zawartość |
|---|---|
| `dotfiles/rofi/` | `config.rasi`, motywy `rofi.rosi` (menu), `rofi2.rosi` (schowek, emoji), `clip-dark-blue.rasi`, `rounded-template.rasi` |
| `dotfiles/cava/` | `config` (główna), `config-bg` (tło), `config-sdl`, `config-eww`, shadery GLSL, motywy `solarized_dark`, `tricolor` |
| `dotfiles/ssh/config` | `github.com` → klucz `~/.ssh/github`, `AddKeysToAgent yes` (samego klucza nie ma w repo) |
| `dotfiles/nvim/` | patrz [nvim.md](nvim.md) |
| `dotfiles/hyprlock/` | blokada ekranu: tło = aktualna tapeta (rozmyta), data, godzina/minuty/sekundy, pole hasła |

## Blokada ekranu – `dotfiles/hyprlock/hyprlock.conf`

- Uruchamianie: `hyprlock` lub `SUPER+M`.
- Pole hasła pokazuje **kropkę na każdy wpisany znak** (`hide_input = false`), więc widać, ile znaków wpisano.
  `BackSpace` usuwa kropkę. Pole jest widoczne cały czas (`fade_on_empty = false`).
- Wygląd kropek: `dots_size` (wielkość), `dots_spacing` (odstęp), `dots_rounding = -1` (okrągłe).
- Kolory ramki: niebieska normalnie, `check_color` przy sprawdzaniu, czerwona (`fail_color`) przy złym haśle.
- Tło: `~/.cache/hyprlock-wallpaper` – link do aktualnej tapety ustawiany przez `switch-random-wallpaper.sh`.
