# Do zrobienia / znane braki

## Przed pierwszym `nixos-rebuild switch`

- [ ] Sprawdź `hardware-configuration.nix` (UUID dysków są z ThinkPada; partycja `/dane` NTFS).
- [ ] `tailnet-b.nix`: uzupełnij `bSuffix` (prawdziwy sufiks MagicDNS), `bOctet`, `bHosts`, nazwę `laptop`.
      Zostawione placeholdery nie zepsują builda, ale tailnet B nie będzie działał poprawnie.
- [ ] Usuń z folderu `nixos-merged` resztki: `shell.nix`, `dotfiles/bash/` oraz stare pliki NvChada w `dotfiles/nvim/lua/`:
      `chadrc.lua`, `mappings.lua`, `options.lua`, foldery `configs/` i `iczo/` (nieużywane, nic ich nie ładuje).

## Mango – `~/.config/mango/config.conf`

- [ ] Dopisz `mango-hintd.conf` i `mango-autostart.conf`.
- [ ] Przenieś potrzebne skróty z Hyprlanda – lista w [keybinds.md](keybinds.md).
- [ ] Klawisze multimedialne (głośność, jasność) – gotowe linijki w [keybinds.md](keybinds.md).
- [ ] Ustaw układ klawiatury `pl` w Mango.
- [ ] Autostart rzeczy, które w Hyprlandzie startowały automatycznie, a w repo ich nie ma:
      pasek (quickshell albo waybar), `mako`, `blueman-applet`,
      ewentualnie `launch-cava-bg.sh`, terminal / brave / discord / keepassxc.
- [ ] Monitory (stare ustawienie: `eDP-1` 1920x1080, `HDMI-A-1` 3840x2160 skala 1.5 nad laptopem).

## Brakujące programy / zamienniki

- [ ] Automatyczna blokada ekranu po bezczynności: brak (hypridle usunięty) – ręczna blokada SUPER+M działa. Usypia tylko przycisk zasilania (`power.nix`).
- [ ] Neovim / STM32: `gcc-arm-embedded` i `openocd` nie są instalowane (debugowanie STM32 w nvim ich wymaga).
- [ ] `kdeconnectd` startował w Hyprlandzie, ale KDE Connect nie jest w pakietach (był zakomentowany).
- [ ] `wayscriber` (SUPER+F3) – nie jest instalowany.
- [ ] `pyenv init` – nie jest już w `.bashrc`; dodaj ręcznie, jeśli używasz pyenv.
- [ ] `clev.nix` – nie da się zbudować bez źródeł `./hintdrive`; nieimportowany.

## Do sprawdzenia po starcie

- [ ] Czy `exec_once` i skróty z `mango-autostart.conf` działają (składnia sprawdzona tylko na papierze).
- [ ] Waybar: moduł `ext/workspaces` z Mango, skrypty `scripts/*.sh`.
- [ ] Obracanie ekranu (iio-sensor-proxy) i klawiatura ekranowa na dotyku.
- [ ] `lazy-lock.json` – jeśli konfiguracja leży w `/etc/nixos` jako root, nvim nie może go zapisać
      (przenieś repo do `~` i podlinkuj `/etc/nixos`, albo zmień właściciela `dotfiles/nvim`).

## Uwaga na Windows

Pliki ze starego repo miały końce linii CRLF (skrypty bash przez to nie działały) – zostały zamienione na LF.
Jeśli trzymasz repo w gicie na Windowsie: `git config core.autocrlf input`.
