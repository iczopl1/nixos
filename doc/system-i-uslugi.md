# System i usługi

Moduły wejściowe są w `configuration_minimal.nix` i `configuration.nix`.
Wspólna baza to `nixos-base.nix`; dyski tej maszyny opisuje lokalny plik
`hardware-configuration.nix`, wykluczony z wersjonowania.

## Boot i użytkownik

`nixos-base.nix` ustawia kernel zen, GRUB w UEFI, wpis EFI w `/boot/efi`,
os-prober, zram, NetworkManager, locale oraz użytkownika `iczo`. Repo zakłada
osobną partycję EFI Linuksa; partycji Windowsa ani jego EFI nie modyfikuje.
`system.stateVersion` pozostaje `25.11` i nie zmienia się przy aktualizacji
kanału.

Użytkownik należy m.in. do grup `networkmanager`, `wheel`, `dialout`, `input`,
`plugdev`, `kvm`, `libvirtd` i `ydotool`. Konkretne UUID i montowania są
per-maszyna; wspólne dane konfiguruje się opcjonalnie w `/etc/nixos/local.nix`.

## Logowanie i pulpit

`services.greetd.enable = false`: system pokazuje zwykły login TTY. Po
zalogowaniu na `tty1` bash uruchamia Mango przez `exec` (`shell.nix`). Wyjście
z Mango wraca do promptu logowania. Quickshell, mako, Linksy, KeePassXC i
pozostałe aplikacje użytkownika startują z `dotfiles/mango/config.conf`.

`mango.nix` rejestruje sesję Mango i konfiguruje portale GTK/wlr, w tym
ScreenCast i Screenshot. `dotfiles.nix` dowiązuje konfigurację Mango,
Quickshell, mako, wlogout i hyprlock. Układ klawiatury to `pl`; orientację
ekranu obsługuje iio-sensor-proxy.

## Sieć i bezpieczeństwo

`security.nix` wyłącza serwer SSH, włącza firewall i dnscrypt-proxy z filtrem
domen. Jawnie otwarte porty obejmują Syncthing (TCP/UDP 22000, UDP 21027) oraz
Linksy UDP 47200. Pozostałe wyjątki są deklarowane przez moduły usług, np. ROS
2 tylko wtedy, gdy włączony jest `ros2.nix`; profil full udostępnia także
izolowane środowisko ROS 2 Humble uruchamiane poleceniem `ros2-humble`.

Tailscale A działa jako zwykła usługa. `tailnet-b.nix` dodaje oddzielną instancję
w network namespace; wartości tailnetu B są konfigurowane w tym module i
powinny być traktowane jako dane lokalne.

## Usługi

| Usługa | Konfiguracja | Uwagi |
|---|---|---|
| PipeWire, PulseAudio compatibility, ALSA, WirePlumber | `services.nix` | dźwięk; `pactl`/`paplay` dostępne z pakietu pulseaudio |
| Syncthing | `services.nix` | użytkownik `iczo`, GUI tylko na `127.0.0.1:8384` |
| Tailscale A | `services.nix` | zwykły interfejs tailnetu |
| Tailscale B | `tailnet-b.nix` | osobny demon i namespace |
| UDisks2 | `services.nix` | montowanie dysków przez udiskie |
| CUPS, HPLIP, Avahi | `services.nix` | drukarki i mDNS |
| TLP, throttled | `services.nix` | bateria i poprawki limitów ThinkPada |
| dnscrypt-proxy | `security.nix` | lokalny resolver DNS z listą blokad |
| libvirt, Bluetooth, keyd | `nixos-base.nix` | wirtualizacja, BT i remap klawiatury |
| TTS mako | `tts-mako.nix` | moduł istnieje, domyślnie wyłączony |

## Zasilanie

`power.nix` ustawia ręczne usypianie: krótki przycisk zasilania usypia, długie
przytrzymanie wyłącza. Klapa, bezczynność i klawisze suspend/hibernate nic nie
robią. TLP stosuje progi ładowania 40–80% dla baterii ThinkPada; `throttled`
obsługuje ograniczenia firmware. `rebuild.sh` może osobno wyłączać turbo na czas
budowania full, jeśli włączony jest znacznik `TURBO_OFF_BUILD`.

## Moduły full

- `ros2.nix` jest importowany przez profil full, otwiera UDP 7400–7500 dla DDS
  i udostępnia środowisko ROS 2 Humble oparte na przypiętym nix-ros-overlay.
  Zapewnia też Podman/Distrobox.
- `webots.nix`, `python.nix` i pozostałe dodatki full nie trafiają do profilu
  minimal.
- Nie kopiuj `hardware-configuration.nix` między maszynami. Przy migracji
  wygeneruj nowy i sprawdź partycję EFI przed buildem.
