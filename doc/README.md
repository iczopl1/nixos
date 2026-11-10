# Dokumentacja konfiguracji NixOS (nixos-merged)

NixOS 25.11, konfiguracja klasyczna (`/etc/nixos`, bez flake'ów, bez home-managera).
Pulpit: **Mango** (kompozytor Wayland). Hyprland usunięty.
Baza: `nixos-selected` (ma pierwszeństwo) + programy i ustawienia ze starej konfiguracji `nixos`.

## Spis

| Plik | O czym |
|---|---|
| [README.md](README.md) | ten plik – mapa konfiguracji: co jest gdzie |
| [keybinds.md](keybinds.md) | skróty klawiszowe Mango, podpowiedzi SUPER+D, stare skróty z Hyprlanda |
| [nvim.md](nvim.md) | Neovim (bez NvChada): start `nvim .`, schowek, skróty, wtyczki, LSP, debugger |
| [komendy.md](komendy.md) | komendy terminala: przebudowa systemu, skrypty, tailnet B, kontenery, TTS |
| [programy.md](programy.md) | lista wszystkich instalowanych programów i w którym pliku są |
| [system-i-uslugi.md](system-i-uslugi.md) | boot, sieć, użytkownik, usługi, Tailscale A/B, firewall, ROS 2 |
| [dotfiles-i-skrypty.md](dotfiles-i-skrypty.md) | dotfiles, linki do `~/.config`, skrypty, tapety, muzyka, waybar |
| [do-zrobienia.md](do-zrobienia.md) | znane braki i rzeczy do dokończenia ręcznie |

## Struktura folderu

```
nixos-merged/
├── configuration.nix        # punkt wejścia: importuje wszystkie moduły poniżej
├── hardware-configuration.nix  # dyski/partycje ThinkPada (wygenerowany)
│
├── system.nix               # boot (GRUB/EFI), sieć, locale, użytkownik iczo, bluetooth, adb, libvirt
├── services.nix             # greetd→mango, pipewire, tailscale, syncthing, układ klawiatury
├── power.nix                # uśpienie tylko przyciskiem zasilania; klapa i bezczynność nic nie robią
├── programs.nix             # prawie wszystkie programy + opentabletdriver, thunar, gnupg, nix-ld
├── python.nix               # Python 3.11 z pakietami naukowymi, pyright, pyenv
├── fonts.nix                # czcionki
├── dotfiles.nix             # linki ~/.config/* → dotfiles/
├── tts-mako.nix             # moduł: czytanie powiadomień na głos (domyślnie wyłączony)
│
├── unstable.nix             # [selected] kanał nixos-unstable jako argument `unstable`
├── mango.nix                # [selected] Mango z łatką slidefade, portale, wpis sesji
├── keyboard-mouse.nix       # [selected] wl-kbptr (łatka vimium), hintd, ydotool, Signal/Ferdium z a11y
├── ros2.nix                 # [selected] podman, distrobox, porty DDS
├── tailnet-b.nix            # [selected] druga sieć Tailscale w osobnym namespace
├── crafts.nix               # [selected] aplikacje Craft budowane ze źródeł
├── clev.nix                 # [selected] NIEIMPORTOWANY (brak źródeł ./hintdrive)
├── mango-tag-slidefade.patch, wl-kbptr-vimium.patch
├── hintd/                   # [selected] demon podpowiedzi SUPER+D (Rust)
├── quickshell/bar/          # [selected] nakładka podpowiedzi dla paska quickshell
├── mango-hintd.conf         # fragment do ~/.config/mango/config.conf (podpowiedzi)
├── mango-autostart.conf     # fragment do ~/.config/mango/config.conf (tapety, muzyka)
│
├── dotfiles/                # nvim, rofi, cava, waybar, ssh, scripts, wallpapers, bgm
├── doc/                     # ta dokumentacja
├── README.md                # podsumowanie scalenia
└── SETUP.md                 # instrukcja instalacji (dla agenta AI, po angielsku)
```

## Gdzie co zmienić – szybka ściąga

| Chcę zmienić… | Plik |
|---|---|
| dodać / usunąć program | `programs.nix` (pakiety Pythona: `python.nix`) |
| czcionki | `fonts.nix` |
| nazwę hosta, strefę czasową, język, grupy użytkownika | `system.nix` |
| bootloader (GRUB, os-prober, timeout) | `system.nix` → `boot.loader` |
| co startuje po włączeniu (sesja) | `services.nix` → `services.greetd` |
| Syncthing, Tailscale, dźwięk | `services.nix` |
| usypianie / zachowanie przy zamknięciu klapy | `power.nix` |
| druga sieć Tailscale (adresy, hosty) | `tailnet-b.nix` → `bOctet`, `bHosts`, `bSuffix` |
| porty dla ROS 2 / kontenery | `ros2.nix` |
| wersję / łatkę Mango | `mango.nix` + `mango-tag-slidefade.patch` |
| skróty klawiszowe pulpitu | `~/.config/mango/config.conf` (fragmenty: `mango-*.conf`) |
| które katalogi trafiają do `~/.config` | `dotfiles.nix` |
| ustawienia nvim / rofi / cava / waybar / hyprlock | `dotfiles/<program>/` |
| tapety | wrzuć pliki do `dotfiles/wallpapers/` |
| muzyka w tle | wrzuć pliki do `dotfiles/bgm/` |
| aplikacje Craft (wersje, które budować) | `crafts.nix` → `apps` |
| czytanie powiadomień na głos | `services.nix` → `services.ttsMako.enable = true` |

## Instalacja / przebudowa

```bash
sudo cp -r nixos-merged/* /etc/nixos/      # pierwszy raz (albo trzymaj repo i linkuj)
sudo nixos-rebuild build                     # sprawdź, czy się buduje
sudo nixos-rebuild switch                    # zastosuj
```

Potrzebny internet (pobierany jest `nixos-unstable` i źródła aplikacji Craft – pierwszy build Craftów trwa długo).
Po pierwszym `switch`: wyloguj się i zaloguj (linki do dotfiles, grupa `ydotool`, zmienne a11y).
Szczegóły: `../SETUP.md`, komendy: [komendy.md](komendy.md).

## Skąd co pochodzi

| Źródło | Co zostało wzięte |
|---|---|
| `nixos-selected` | wszystkie moduły bez zmian (mango, keyboard-mouse, ros2, tailnet-b, crafts, unstable, clev), hintd, quickshell, łatki, `mango-hintd.conf`, `SETUP.md` |
| `nixos/modules/system` | `system.nix` (+ grupa `ydotool`, czujnik iio) |
| `nixos/modules/services` | `services.nix` (sesja Hyprland → Mango), `tts-mako.nix` |
| `nixos/modules/programs`, `home.nix`, `hosts/*`, `TestLocal.nix` | `programs.nix`, `python.nix`, `fonts.nix` |
| `nixos/home.nix` (`home.file`) | `dotfiles.nix` |
| `nixos/dotfiles` | `dotfiles/` (bez `hypr/` i `bash/`; skrypty z `hypr/` niezależne od Hyprlanda → `dotfiles/scripts/`) |
| `nixos/dotfiles/hypr/hyprland.conf` | `mango-autostart.conf` (tylko tapety i muzyka) |

Celowo **nie** przeniesione: Hyprland i wszystko z nim związane, aliasy i funkcje bash ze starego `home.nix`, `flake.nix`, `hosts/pc`.
