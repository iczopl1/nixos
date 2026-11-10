# Komendy terminala

Brak własnych aliasów bash – obowiązują tylko komendy z nixos-selected i programów z konfiguracji.
Aliasy i funkcje ze starego `home.nix` (`update`, `ll`, `gs`, `u`, `h` …) celowo **nie** zostały przeniesione.

## System (NixOS)

| Komenda | Działanie |
|---|---|
| `sudo nixos-rebuild build` | zbuduj bez przełączania (test, czy konfiguracja jest poprawna) |
| `sudo nixos-rebuild switch` | zbuduj i zastosuj |
| `sudo nixos-rebuild test` | zastosuj do restartu (bez wpisu w bootloaderze) |
| `sudo nixos-rebuild switch --rollback` | wróć do poprzedniej generacji |
| `sudo nix-collect-garbage -d` | usuń stare generacje i nieużywane pakiety |
| `nix-channel --list` | kanały (konfiguracja klasyczna, bez flake) |

## Mango (kompozytor)

| Komenda | Działanie |
|---|---|
| `mango -c ~/.config/mango/config.conf -p` | sprawdź składnię konfiguracji |
| `mmsg dispatch setkeymode,default` | wróć do domyślnego trybu klawiszy |
| `mmsg …` | sterowanie Mango z terminala/skryptów (używa go hintd i Hints.qml) |

## Podpowiedzi SUPER+D (hintd)

`hintd` startuje z `config.conf` (`exec_once=setsid hintd`). Gniazdo: `$XDG_RUNTIME_DIR/hintd.sock`.

| Komenda | Działanie |
|---|---|
| `echo state \| socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock` | `idle` albo `hold` |
| `echo release \| socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock` | puść trzymany przycisk |
| `echo boxes \| socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hintd.sock` | lista znalezionych pól |
| `HINTD_DEBUG=1 hintd` | uruchom z czasami kroków na stderr |
| `HINTD_NO_VISION=1 hintd` | bez pól wykrywanych ze zrzutu ekranu |

Więcej: `hintd/README.md`.

## Tapety i muzyka (`~/.config/scripts`)

| Komenda | Działanie |
|---|---|
| `~/.config/scripts/switch-random-wallpaper.sh` | losowa tapeta + motyw kolorów (pywal) |
| `~/.config/scripts/rotate-random-wallpaper.sh` | zmieniaj tapetę co `INTERVAL` s (domyślnie 3600) |
| `~/.config/scripts/bgm-power-monitor.sh` | demon muzyki w tle (gra na zasilaniu sieciowym) |
| `~/.config/scripts/bgm-power-monitor.sh toggle` | włącz/wyłącz muzykę ręcznie |
| `~/.config/scripts/bgm-power-monitor.sh skip` | następny utwór |
| `~/.config/scripts/bgm-current-playlist.sh` | wygeneruj/pokaż dzisiejszą playlistę |
| `~/.config/scripts/emoji-menu.sh` | wybór emoji w rofi |
| `~/.config/scripts/waybar-toggle.sh` | pokaż/ukryj waybar |
| `~/.config/scripts/toggle-wvkbd.sh` | klawiatura ekranowa |
| `~/.config/scripts/launch-cava-bg.sh` | wizualizer cava w tle (kitty panel) |

Zmienne: `WALLPAPER_DIR`, `BGM_DIR`, `BGM_VOLUME` (50), `INTERVAL`, `TRANSITION_TYPE` (`grow`), `TRANSITION_DURATION` (10).
Logi: `~/.cache/rotate-random-wallpaper.log`, `~/.cache/bgm-power-monitor.log`, `~/.cache/wal-apply-theme.log`.

## Tailscale

| Komenda | Działanie |
|---|---|
| `tailscale up` / `tailscale status` | tailnet A (zwykły, `tailscale0`) |
| `sudo tailscale --socket=/run/tailscale-b/tailscaled.sock up` | pierwsze logowanie do tailnet B |
| `tailscale --socket=/run/tailscale-b/tailscaled.sock status` | status tailnet B |
| `ssh host1` / `ping 10.77.0.1` | host z tailnet B (adres `100.77.x.x` widoczny jako `10.77.x.x`) |
| `systemctl status tailscaled-b tsb-netns` | usługi tailnet B |
| `sudo ip netns exec tsb ip a` | podgląd namespace'u tailnet B |

## Kontenery / ROS 2

| Komenda | Działanie |
|---|---|
| `podman …` / `docker …` | podman (z aliasem `docker`) |
| `podman-compose up` | compose |
| `distrobox create -n ros -i <obraz>` / `distrobox enter ros` | kontener z ROS 2 |

## Python

| Komenda | Działanie |
|---|---|
| `python3` | Python 3.11 z pakietami z `python.nix` |
| `python3 -m venv .venv && source .venv/bin/activate` | środowisko projektu |
| `pyenv install 3.12.4 && pyenv local 3.12.4` | inna wersja Pythona dla projektu (`PYENV_ROOT=~/.pyenv`) |
| `jupyter lab` | JupyterLab |

Uwaga: `pyenv init` nie jest już dopisywany do `.bashrc` (był w starym `home.nix`) – dodaj ręcznie, jeśli używasz pyenv.

## Czytanie powiadomień (tts-mako, gdy `services.ttsMako.enable = true`)

| Komenda | Działanie |
|---|---|
| `ttsmako-install-voices` | pobierz głosy piper do `~/.local/share/ttsmako/voices` |
| `ttsmako-toggle` | włącz/wyłącz czytanie |
| `ttsmako-skip` | przerwij bieżące czytanie |
| `systemctl --user status ttsmako-listen` | stan usługi |

## Aplikacje Craft (`crafts.nix`)

Każda aplikacja ma GUI `<nazwa>` i wersję CLI `<nazwa>-cli`:
`photocraft`, `vectorcraft`, `filmcraft`, `lightcraft`, `pdfcraft`, `effectcraft`, `designcraft`,
`gridcraft`, `cadcraft`, `deckcraft`, `soundcraft`, `wordcraft`.

## Inne przydatne

| Komenda | Działanie |
|---|---|
| `xdg-open http://127.0.0.1:8384` | panel Syncthing |
| `wpctl status` / `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` | dźwięk |
| `brightnessctl set 10%+` | jasność |
| `bluetoothctl` / `blueman-manager` | Bluetooth |
| `nmtui` / `nm-applet` | sieć |
| `cliphist list` | historia schowka (gdy działa `wl-paste --watch cliphist store`) |
| `grim -g "$(slurp)" - \| wl-copy` | zrzut zaznaczenia do schowka |
| `adb devices` | Android (grupa `adbusers`) |
| `virt-manager` | nie zainstalowany; libvirtd działa (`virsh`) |
