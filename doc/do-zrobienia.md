# Ręczna konfiguracja i znane ograniczenia

Aktualne zadania repozytorium są w [TODO.md](../TODO.md), a problemy pakietów i
znane obejścia w [BROKEN.md](../BROKEN.md). Ta strona zawiera tylko czynności,
których nie wykonuje automatycznie konfiguracja.

## Przygotowanie hosta

- Sprawdź `/etc/nixos/hardware-configuration.nix` na każdej maszynie. Plik jest
  per-host i nie należy go kopiować z innego komputera.
- Dostosuj `/etc/nixos/local.nix` dla dysków NTFS, ustawień CPU lub modułów
  wymaganych tylko na tym hoście. Ten plik jest importowany w obu profilach;
  nie umieszczaj w nim modułów, które mają działać wyłącznie w full.
- Ustaw właściwe dane `tailnet-b.nix` przed użyciem tailnetu B. Nie publikuj
  sekretów ani kluczy prywatnych w repozytorium.
- Checkouty Unitree i G1-Prz-Controll pozostają osobnymi repozytoriami. Na
  obecnym hoście dowiązania są w `~/Unitree/` i `~/unitree_sdk2*`.

## Pierwsze logowanie

- Przy pierwszym uruchomieniu nowej generacji sprawdź katalogi `~/.config/mango`,
  `quickshell`, `waybar` i `hypr`; tmpfiles podmienia je na dowiązania do repo.
- Zaloguj się przez TTY na `tty1`; Mango startuje z login shella. Quickshell,
  skróty, usługi i autostart są zdefiniowane w `dotfiles/mango/config.conf`.
- Sprawdź urządzenia audio, ekran zewnętrzny i obrót ekranu na konkretnym
  sprzęcie.
- Jeśli `lazy-lock.json` nie jest zapisywalny, przenieś repo do katalogu
  użytkownika albo popraw prawa dostępu do `dotfiles/nvim`.

## Znane ograniczenia

- ROS 2 Humble z modułu full `ros2.nix` uruchamia się przez `ros2-humble`;
  checkoutowy `unitree_ros2/setup.sh` wskazuje Foxy (`/opt/ros/foxy`) i nie
  pasuje do tego środowiska. Używaj `ros2-humble` oraz `colcon`.
- Podgląd nagrań MuJoCo wymaga pakietu `mujoco`, modelu G1 i poprawnych ścieżek;
  checkout `unitree_mujoco` może nie zawierać przygotowanego venv.
- Część upstreamowych pakietów opisana jako zablokowana ma alternatywę lub
  obejście wymienione w `BROKEN.md`.
