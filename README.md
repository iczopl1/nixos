# nixos-merged

Scalona konfiguracja: **nixos-selected** (baza, ma pierwszeństwo) + stara **nixos** (flake + home-manager).

Pełna dokumentacja (co jest ustawione i gdzie, skróty, nvim, komendy): **[doc/README.md](doc/README.md)**.
Styl jak w nixos-selected: klasyczny `/etc/nixos`, bez flake'ów i bez home-managera. Bez Hyprlanda – sesja to Mango.

## Pliki

| Plik | Skąd | Co robi |
|---|---|---|
| `configuration.nix` | nowy | importuje wszystkie moduły |
| `unstable.nix`, `mango.nix`, `keyboard-mouse.nix`, `ros2.nix`, `tailnet-b.nix`, `crafts.nix`, `clev.nix`, `*.patch`, `hintd/`, `quickshell/`, `mango-hintd.conf` | nixos-selected | skopiowane 1:1 (`clev.nix` nieimportowany – brak `./hintdrive`) |
| `system.nix` | nixos `modules/system` | GRUB/EFI, sieć, locale PL, użytkownik iczo, bluetooth, adb, libvirt |
| `services.nix` | nixos `modules/services` | greetd → **mango**, pipewire, tailscale, syncthing, xkb pl |
| `programs.nix` | nixos `modules/programs` + `home.nix` + `hosts/*` + `TestLocal.nix` | wszystkie programy (bez Hyprlanda) |
| `python.nix`, `tts-mako.nix` | nixos | bez zmian |
| `fonts.nix` | nixos `hosts/*` | czcionki |
| `dotfiles.nix` | nixos `home.nix` (tylko `home.file`) | linki do dotfiles |
| `hardware-configuration.nix` | nixos `hosts/laptop` | dyski ThinkPada |
| `dotfiles/` | nixos `dotfiles` (nvim przepisany bez NvChada) | nvim, rofi, cava, waybar, ssh (→ ~/.ssh/config), `scripts/`, **`wallpapers/`**, **`bgm/`** |
| `mango-autostart.conf` | nixos `hypr/hyprland.conf` + `keybinds.conf` | autostart tapet i muzyki + skróty SUPER+F10/F12/Insert |

## Zmiany względem starej konfiguracji

- **Usunięte (Hyprland):** `programs.hyprland`, hypridle, iio-hyprland, xdg-desktop-portal-hyprland, `~/.config/hypr`.
- **Zamienniki:** sesja greetd → `mango`; portale z `mango.nix`; obracanie ekranu → `hardware.sensor.iio.enable` (iio-sensor-proxy, używa go mango.nix).
- **home-manager → NixOS:** pakiety z `home.nix` są w `programs.nix`, dotfiles linkowane przez `systemd.user.tmpfiles` (folder `dotfiles/` obok konfiguracji, nie w /nix/store).
- **Komendy powłoki:** tylko te z nixos-selected. Ze starej konfiguracji NIE przeniesiono aliasów i funkcji bash (`update*`, `ll`, `g*`, `u`/`uu`/`_histpick` itd.), integracji zoxide/fzf z bashem ani `dotfiles/bash` (pakiety `zoxide` i `fzf` zostały).
- **Kolizje:** `jdk21` i `clang` mają niższy priorytet (`java` = jdk17 jak `JAVA_HOME`, `cc` = gcc).
- **Użytkownik** dostał grupę `ydotool` (wymagana przez hintd / tryb kursora).
- **Waybar:** `hyprland/workspaces` → `ext/workspaces` (Mango), `custom/keyboard-layout` pokazuje stałe `pl` (bez hyprctl), skrypty bgm z `~/.config/scripts/`. Usunięte skrypty oparte tylko na hyprctl: `terminal-waybar.sh`, `toggle-waybar-empty-workspace.sh`, `watch-waybar-workspaces.sh`.
- **`dotfiles/scripts/`:** skrypty z dawnego `hypr/` niezależne od kompozytora (tapety, emoji, cava-bg, bgm, wvkbd, pywal).
- **Tapety i muzyka w folderze konfiguracji:** skrypty szukają tapet w `dotfiles/wallpapers/` (wcześniej `~/wpps`) i muzyki w `dotfiles/bgm/` (wcześniej `~/bgm/lofi`). Ścieżka liczona jest od prawdziwego położenia skryptu, więc działa przez link `~/.config/scripts`. Nadpisanie: `WALLPAPER_DIR`, `BGM_DIR`.
- **Końce linii:** część plików ze starego repo miała końce linii Windows (CRLF) – skrypty bash by się nie uruchomiły. Wszystko przekonwertowane na LF.
- **Pominięte:** `flake.nix`/`flake.lock`, `hosts/pc` (był szablonem z błędem składni), `logs.txt`, `comand.sh`, `colcon_ws` (link do zewnętrznego repo), `.git`.

## Do zrobienia ręcznie

- Dopisz `mango-autostart.conf` i `mango-hintd.conf` do `~/.config/mango/config.conf`. Pozostałe skróty z `hypr/keybinds.conf` nie są przepisane.
- Wrzuć tapety do `dotfiles/wallpapers/` i muzykę do `dotfiles/bgm/` (pliki multimedialne nie są kopiowane ze starego `$HOME`).
- Blokada ekranu: hyprlock (`dotfiles/hyprlock/`, SUPER+M) pokazuje kropkę na każdy wpisany znak; automatycznej blokady (hypridle) nie ma.
- Uzupełnij dane tailnet B w `tailnet-b.nix` (SETUP.md → „Fill in”).
