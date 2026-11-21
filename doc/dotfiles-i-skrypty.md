# Dotfiles i skrypty

Ustawienia użytkownika są w `dotfiles/`; `shell.nix` i `dotfiles.nix` tworzą
dowiązania do katalogu repo przy logowaniu. Mango i Quickshell nie wymagają
ręcznego kopiowania plików.

## Dowiązania

| Ścieżka użytkownika | Źródło |
|---|---|
| `~/.config/mango` | `dotfiles/mango` |
| `~/.config/quickshell` | `dotfiles/quickshell` |
| `~/.config/nvim` | `dotfiles/nvim` |
| `~/.config/rofi`, `cava`, `waybar`, `alacritty` | odpowiadające foldery w `dotfiles/` |
| `~/.config/scripts` | `dotfiles/scripts` (tmpfiles rules z `shell.nix` i `dotfiles.nix`) |
| `~/.config/mako/config` | `dotfiles/mako/config` |
| `~/.config/hypr` | `dotfiles/hypr` (skrypty pomocnicze używane przez Mango/Quickshell) |
| `~/syshelp` | `dotfiles/syshelp` (hintd, efekty i gesty dotykowe) |
| `~/bin/rd`, `~/.local/bin/th` | narzędzia z konfiguracji Quickshell |
| `~/.config/wlogout/layout` | `dotfiles/wlogout/layout` |
| `~/.ssh/config` | `dotfiles/ssh/config` |
| `~/.config/wallpapers` | `dotfiles/wallpapers` |

Tmpfiles linkuje katalogi konfiguracji bezpośrednio do repozytorium. Mango dzieli
ustawienia na `config.conf` i pliki `mango-*.conf`; skróty pozostają w głównym
pliku. Nowy pasek uruchamia `qs -c bar`.

## Mango i Quickshell

`dotfiles/quickshell/` zawiera pasek, widgety stanu, skróty, podpowiedzi AT-SPI,
animację pisania i efekty pulpitu. Komunikacja między konfiguracją a widgetami
używa lokalnych socketów w `$XDG_RUNTIME_DIR`.

`bash-suggest/` zawiera podpowiedzi historii, komend, aliasów i funkcji Bash.
`shell.nix` buduje program jako pakiet NixOS i dołącza jego `init.bash` do
interaktywnej powłoki.

Najważniejsze skrypty:

| Skrypt | Funkcja |
|---|---|
| `effects-ctl.sh` (`effects`) | blur/shadows/animations/layer/particles/wpm/cava/opacity/bar jednym programem; stan w `~/.config/mango-effects.conf` (komentarz = wyłączone); `effects reapply`/`edit` |
| `battery-effects-monitor.sh` | gasi wszystkie efekty "specjalne" na baterii, wraca na AC (woła `effects reapply`) |
| `screenrec-toggle.sh` | nagrywanie ekranu |
| `syncthing-status.sh` | status synchronizacji do widgetu |
| `phone-status.sh`, `bt-headset.sh` | stan telefonu i przełączanie zestawu BT |
| `throttle.sh` | ograniczanie pasma przez tc |
| `prz-schedule.py` | pobieranie planu zajęć PRz, opcjonalnie ICS |
| `switch-random-wallpaper.sh`, `rotate-random-wallpaper.sh` | tapeta losowa i rotacja |
| `bgm-power-monitor.sh`, `bgm-current-playlist.sh` | muzyka zależna od zasilania i playlista |
| `emoji-menu.sh`, `agent.sh` | menu emoji i podsumowanie narzędzi |

Skróty startowe, autostart oraz layout okien są w jednym źródle:
[`dotfiles/mango/config.conf`](../dotfiles/mango/config.conf). Tapety i pliki
muzyczne są w `dotfiles/wallpapers/` i `dotfiles/bgm/`.

## Pozostałe ustawienia

- `dotfiles/rofi/` — motywy menu aplikacji, okien i schowka.
- `dotfiles/cava/` — konfiguracje, shadery i motywy wizualizera.
- `dotfiles/waybar/` — moduły, skrypty i kolory odczytywane także przez Quickshell.
- `dotfiles/alacritty/alacritty.toml` — terminal i skróty rozmiaru czcionki.
- `dotfiles/nvim/` — Neovim; szczegóły w [nvim.md](nvim.md).
- `dotfiles/ssh/config` — ustawienia klienta SSH; klucze prywatne nie są w repo.
- `dotfiles/mako/config` — timeout i wygląd powiadomień.
- `dotfiles/wlogout/layout` — menu wylogowania/zasilania; Lock uruchamia hyprlock.

`mango-autostart.conf` i `mango-hintd.conf` są zachowanymi fragmentami
referencyjnymi. Ich funkcje znajdują się już w pełnej konfiguracji Mango;
nie wklejaj ich ponownie, bo utworzą zdublowane skróty i autostarty.

Link hyprlock jest utrzymywany ze względu na domyślną ścieżkę aplikacji; nie
oznacza używania kompozytora Hyprland.
