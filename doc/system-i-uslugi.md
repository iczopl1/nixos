# System i usługi

## Boot (`system.nix`)

| Ustawienie | Wartość |
|---|---|
| Bootloader | GRUB, EFI, `device = "nodev"` |
| Inne systemy | `useOSProber = true` (wykrywa np. Windowsa) |
| Partycja EFI | `/boot/efi` |
| Timeout menu | 10 s |
| Moduły jądra | `kvm-intel` (hardware), `uinput` (programs.nix) |
| `ip_forward` | włączony (wymaga go tailnet B) |

## Dyski (`hardware-configuration.nix`)

| Punkt montowania | Typ |
|---|---|
| `/` | ext4 |
| `/boot/efi` | vfat |
| `/dane` | NTFS (wspólny z Windowsem) |
| swap | partycja |

UUID są z laptopa ThinkPad. Na innym komputerze wygeneruj nowy plik: `nixos-generate-config --show-hardware-config`.

## Sieć i region (`system.nix`)

| Ustawienie | Wartość |
|---|---|
| Nazwa hosta | `ThinkPadNIX` |
| Sieć | NetworkManager |
| Strefa czasowa | Europe/Warsaw |
| Język systemu | en_US.UTF-8, formaty (data, waluta, papier…) pl_PL.UTF-8 |
| Klawiatura konsoli | `pl2` |
| Klawiatura X11/xkb | `pl` (`services.nix`) – w Mango ustaw też w `config.conf` |

## Użytkownik

`iczo` (zwykły użytkownik), grupy: `networkmanager`, `wheel` (sudo), `adbusers`, `libvirtd`, `kvm`, `ydotool`.
Hasło ustawiasz `passwd` – nie ma go w konfiguracji.

## Sesja graficzna (`services.nix`, `mango.nix`)

- `greetd` startuje od razu `mango` jako `iczo` (bez ekranu logowania – jak wcześniej z Hyprlandem).
  W `services.nix` jest zakomentowana alternatywa z `tuigreet` (ekran logowania + wybór sesji).
- `mango.nix` rejestruje sesję `mango` dla menedżerów logowania i ustawia portale:
  ogólnie GTK, zrzuty i nagrywanie ekranu – wlr.
- Czujnik orientacji ekranu: `hardware.sensor.iio.enable` + `iio-sensor-proxy` startujący z systemem.
- Dostępność (a11y): `keyboard-mouse.nix` opakowuje Signal i Ferdium flagą `--force-renderer-accessibility`,
  żeby SUPER+D widział ich przyciski.

## Usługi

| Usługa | Plik | Uwagi |
|---|---|---|
| PipeWire (+ Pulse, ALSA, WirePlumber) | `services.nix` | dźwięk |
| Bluetooth + Blueman | `system.nix` | włączony przy starcie |
| Tailscale (tailnet A) | `services.nix` | interfejs `tailscale0` |
| tailscaled-b + tsb-netns (tailnet B) | `tailnet-b.nix` | niżej |
| Syncthing | `services.nix` | jako `iczo`, panel `127.0.0.1:8384`, otwarte domyślne porty |
| libvirtd | `system.nix` | maszyny wirtualne |
| adb | `system.nix` | Android |
| podman | `ros2.nix` | kontenery, `docker` = podman |
| ydotoold | `keyboard-mouse.nix` | sterowanie kursorem |
| OpenTabletDriver | `programs.nix` | tablety graficzne |
| gnupg-agent (SSH) | `programs.nix` | |
| ttsmako-listen / ttsmako-avrcp-watch | `tts-mako.nix` | **wyłączone** (`services.ttsMako.enable = false`) |
| dconf | `system.nix` | ustawienia GTK |

## Tailnet B (`tailnet-b.nix`)

Druga sieć Tailscale obok zwykłej, bez konfliktu tras i DNS:

- osobny `tailscaled` w namespace sieciowym `tsb` (tun `tailscale1`, port 41642, stan w `/var/lib/tailscale-b`),
- para veth: host `vtsb0` = `10.250.0.1`, namespace `vtsb1` = `10.250.0.2`,
- adresy tailnet B `100.77.x.x` są widoczne na hoście jako `10.77.x.x` (NETMAP 1:1),
- nazwy hostów B w `/etc/hosts` (`host1` … `host6`, `*.tailnet-b.example.ts.net`),
- DNS dla tailscaled-b: 9.9.9.9 / 1.1.1.1 (nie rusza DNS tailnetu A),
- firewall: namespace wychodzi tylko do internetu, nic nie jest przekazywane do/z tailnet A, do LAN tylko UDP na wysokich portach.

Do uzupełnienia: `bSuffix`, `bOctet`, `bHosts`, nazwa `laptop` – patrz [do-zrobienia.md](do-zrobienia.md).

## Zasilanie i usypianie (`power.nix`)

Laptop **sam się nie usypia** – może zostać zamknięty i liczyć dalej (na zasilaczu i na baterii).
Uśpić go można tylko ręcznie.

| Zdarzenie | Zachowanie |
|---|---|
| przycisk zasilania – krótko | **uśpienie** (`HandlePowerKey = suspend`) |
| przycisk zasilania – długo | wyłączenie (`HandlePowerKeyLongPress = poweroff`) |
| `systemctl suspend` | uśpienie |
| zamknięcie klapy (bateria / zasilacz / z monitorem) | nic (`HandleLidSwitch*` = `ignore`) |
| bezczynność | nic (`IdleAction = ignore`) |
| klawisz uśpienia / hibernacji (Fn) | nic |

Uwagi:
- W czasie uśpienia nic się nie liczy – przed naciśnięciem przycisku upewnij się, że zadanie skończone.
- Na baterii nie ma automatycznego uśpienia przy niskim poziomie – laptop rozładuje się do zera.
- Przy zamkniętej klapie ekran może nadal świecić (Mango go nie wyłącza).
- Ekran nie blokuje się przy usypianiu – blokuj ręcznie SUPER+M przed naciśnięciem przycisku.
- Usypianie klapą: w `power.nix` ustaw `HandleLidSwitch = "suspend"`.

## Firewall – otwarte porty

| Port | Po co | Plik |
|---|---|---|
| UDP 7400–7500 | ROS 2 / DDS discovery | `ros2.nix` |
| TCP 22000, UDP 22000, 21027 | Syncthing | `services.nix` (`openDefaultPorts`) |

## Wersja

`system.stateVersion = "25.11"` – nie zmieniaj przy aktualizacjach.
Kanał bazowy: nixos-25.11 (systemowy `nix-channel`). `unstable.nix` pobiera **niepinowany** nixos-unstable (Mango, Signal);
`crafts.nix` ma własne przypięte nixpkgs, rust-overlay i crane.
