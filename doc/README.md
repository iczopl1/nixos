# Dokumentacja konfiguracji NixOS

Konfiguracja jest klasyczna (bez flake'ów i Home Managera), z dwoma profilami:
minimal (`configuration_minimal.nix`) i full (`configuration.nix`). System używa
Mango jako kompozytora Wayland oraz Quickshell jako paska i nakładek.

## Spis dokumentacji

| Plik | Temat |
|---|---|
| [../README.md](../README.md) | podsumowanie projektu i mapa repo |
| [system-i-uslugi.md](system-i-uslugi.md) | boot, logowanie, sieć, dźwięk, firewall, usługi i zasilanie |
| [programy.md](programy.md) | pakiety, profile minimal/full i Python |
| [komendy.md](komendy.md) | rebuild, aliasy, skrypty i narzędzia |
| [keybinds.md](keybinds.md) | aktywne skróty Mango z `dotfiles/mango/config.conf` |
| [dotfiles-i-skrypty.md](dotfiles-i-skrypty.md) | dowiązania, Quickshell i skrypty użytkownika |
| [nvim.md](nvim.md) | konfiguracja Neovima, pluginy, LSP, formatowanie i debugowanie |
| [do-zrobienia.md](do-zrobienia.md) | rzeczy do wykonania ręcznie i ograniczenia |

## Źródło prawdy

Konfigurację opisują pliki `.nix` oraz pliki w `dotfiles/`. Zasady i polityki
projektu są w [MASTER.md](../MASTER.md), pakiety z wcześniejszymi problemami w
[BROKEN.md](../BROKEN.md), a aktualny postęp w [TODO.md](../TODO.md).
Dokumentacja jest opisem użytkowym, nie zastępuje tych źródeł.

## Główne moduły

```text
configuration_minimal.nix  wspólna baza, Mango, bezpieczeństwo, usługi i programy minimal
configuration.nix          import minimal + dodatki full
nixos-base.nix              kernel, GRUB, użytkownik, sieć i sprzęt
services.nix                PipeWire, Syncthing, Tailscale, drukowanie i zasilanie
security.nix                firewall, DNSCrypt i wyłączony serwer SSH
programs_minimal.nix         narzędzia dostępne w minimal
programs.nix                programy full
python.nix                  Python 3.13 i pakiety full
ros2.nix                    ROS 2 Humble, Podman/Distrobox i porty DDS (full)
dotfiles.nix, shell.nix      pliki użytkownika, aliasy, funkcje i dowiązania
```

Pliki `/etc/nixos/hardware-configuration.nix` i `local.nix` są per-maszyna i
wykluczone z wersjonowania. `configuration_minimal.nix` importuje oba, więc ustawienia
z `local.nix` trafiają do minimal oraz full; `ros2.nix` jest oddzielnym importem full.
