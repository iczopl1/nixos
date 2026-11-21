# Instalacja i praca z konfiguracją

Repozytorium używa klasycznej konfiguracji NixOS, bez flake'ów i Home Managera.
Pliki wejściowe to `configuration_minimal.nix` i `configuration.nix`; wybór
profilu zapisuje instalator w `/etc/nixos/PROFILE`.

## Nowa maszyna

Uruchom `./auto.sh` w sklonowanym repo. Skrypt wykrywa nową maszynę na podstawie
UUID partycji `/`, przygotowuje `hardware-configuration.nix` w `/etc/nixos`,
pyta o profil i najpierw buduje minimal. Nie formatuje partycji. Zweryfikuj
proponowaną partycję EFI Linuksa; partycje Windowsa są nietykalne.

Wymagane lokalne pliki:

- `/etc/nixos/hardware-configuration.nix` — generowany dla danej maszyny, poza repo.
- `/etc/nixos/local.nix` — opcjonalne montowania i ustawienia hosta. Jest
  importowany przez minimal i full, więc nie umieszczaj w nim modułów full-only.
- `/etc/nixos/PROFILE` — `minimal` albo `full`, tworzony przez `auto.sh`.
- `/etc/nixos/TURBO_OFF_BUILD` — opcjonalny znacznik dla starszych ThinkPadów;
  `rebuild.sh` wyłącza turbo tylko na czas budowania full i przywraca poprzedni stan.

## Przebudowa

```bash
./rebuild.sh -n "opis zmiany"  # sprawdzenia i dry-build
./rebuild.sh "opis zmiany"     # build boot, commit po sukcesie, synchronizacja /etc/nixos
```

Skrypt sprawdza składnię, uruchamia lintery, kontroluje bezpieczeństwo i buduje
wybrany profil. Commit oraz kopiowanie do `/etc/nixos` następują wyłącznie po
udanym buildzie. Nie używaj `nixos-rebuild switch` na niesprawdzonej konfiguracji.
Po udanym buildzie uruchom ponownie komputer, aby wystartować nową generację.

## Układ i zależności

- `configuration.nix` importuje `configuration_minimal.nix` i moduły full.
- `unstable.nix` dostarcza argument `unstable` dla wybranych pakietów.
- `keyboard-mouse.nix` buduje `hintd` ze źródeł `dotfiles/syshelp/hint-atspi/` oraz `wl-kbptr`.
- `mango.nix` używa `mango-tag-slidefade.patch`.
- `dotfiles.nix` i `shell.nix` tworzą dowiązania użytkownika do `dotfiles/`.
- `ros2.nix` jest importowany wyłącznie przez `configuration.nix` (full).
  Moduł udostępnia ROS 2 Humble poleceniem `ros2-humble`, Podman/Distrobox i
  zakres UDP DDS. Dla G1 ustaw `UNITREE_ROS_INTERFACE` na interfejs Ethernetu.
- `dotfiles/syshelp/hintdrive/clev.nix` udostępnia `clev` i `clev-goal`.

`dotfiles/` obok konfiguracji musi pozostać dostępny po synchronizacji do
`/etc/nixos`, ponieważ dowiązania wskazują bezpośrednio na te pliki. Tmpfiles
podmienia wskazane katalogi konfiguracji na dowiązania do repozytorium.

## Dokumentacja i zasady

- [README.md](README.md) — punkt wejścia i mapa plików.
- [MASTER.md](MASTER.md) — nadrzędne zasady repozytorium.
- [BROKEN.md](BROKEN.md) — pakiety i ścieżki, które wcześniej sprawiały problemy.
- [doc/README.md](doc/README.md) — spis dokumentacji.

Nie dodawaj pakietu oznaczonego w `BROKEN.md` bez rozwiązania przyczyny. Zmiany
przy ROS trzymaj w oddzielnym commicie i zweryfikuj osobno. Zadania z TODO
wdrażaj zgodnie z priorytetem i zasadą jednego podpunktu na commit.
