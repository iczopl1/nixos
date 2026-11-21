# TODO – lista zadań

> Format: `[ ]` do zrobienia · `[~]` w trakcie · `[x]` zrobione · `[-]` pominięte
> Jeden podpunkt = jeden commit. Kolejność zatwierdza użytkownik (MASTER §17).
> Historia zrobionych zadań (T0.x–T3.x, wszystkie poza T2.40): `git log` (commity `T*.*: ...`)
> i `BROKEN.md` (problemy, przyczyny, obejścia). Ten plik trzyma tylko to, co jest otwarte.

---

## Do zrobienia

- [x] **T2.40** Program throttlujący CPU przy przegrzaniu: 85°C → ogranicz moc, aż spadnie do 70°C
        – **STATUS (2026-11-20): zaimplementowane w working tree, NIEPRZETESTOWANE** (agent nie
          miał sudo w tej sesji – nie mógł zbudować ani zweryfikować zapisu do sysfs). Patrz
          sekcja "Zaległe do zrobienia przez użytkownika" niżej po szczegóły co sprawdzić.
          Pliki: `dotfiles/quickshell/bar/ThermalThrottle.qml` (nowy), `bar/shell.qml`
          (instancjonowanie), `dotfiles/scripts/effects-ctl.sh` (`cpu-throttle` toggle),
          `services.nix` (`systemd.tmpfiles.rules`, komentarz o konflikcie z TLP).
        – **Odchylenie od specyfikacji niżej (sprawdzone w kodzie, nie zgadywane):**
          `nightlight` NIE używa `~/.config/mango-effects.conf` (comment-to-disable) – używa
          `~/.config/mango-effects` (LEGACY_STATE, `legacy_state_get/set`, format
          `klucz=wartość`). `cpu-throttle` idzie tym samym, realnym wzorcem: klucz
          `cpu-throttle=on|off` w LEGACY_STATE, domyślnie ON gdy klucz nieobecny. Temperatura:
          ThermalThrottle.qml NIE czyta `/sys/class/thermal/thermal_zone*/temp` osobnym
          procesem – używa już istniejącego `Sys.tempC` (singleton `Sys.qml`, T2.33), żeby
          nie mieć dwóch implementacji czytających te same pliki. Uprawnienia: `systemd.tmpfiles.rules`
          z `0644 iczo root` (nie grupą "iczo" – taka grupa nie istnieje, `isNormalUser` w
          `nixos-base.nix` nie definiuje osobnej grupy o nazwie usera).
        – Powód: X250 pod długim obciążeniem (np. build full, kompilacja) może grzać się mocno
          mimo `services.throttled` (T1.15 – throttled naprawia tylko BIOS-owe PL1/PL2, nie
          chroni przed przegrzaniem przy realnym długim 100% obciążeniu). To osobny mechanizm:
          nie "napraw sztuczne dławienie", a "aktywnie dław, gdy naprawdę gorąco".
        – **DECYZJA UŻYTKOWNIKA (2026-11-20): logika ma działać W Quickshell** (QML/Timer w
          `dotfiles/quickshell/bar/`), NIE jako osobny bash+systemd demon (to była pierwsza
          propozycja z researchu, odrzucona). Powiązane: `/sys/class/thermal/thermal_zone*/temp`
          (odczyt, ten sam wzorzec co bar T2.33), throttle przez
          `/sys/devices/system/cpu/intel_pstate/max_perf_pct` (zapis – NIE to samo co `no_turbo`/
          `TURBO_OFF_BUILD` z rebuild.sh, max_perf_pct ogranicza częstotliwość ogólnie).
        – **Wyłącznik awaryjny przez `effects`/komentarz:** TO NIE jest jeden z 9 "specjalnych"
          efektów (blur/shadows/particles/wpm-*/cava) – te gasi `battery-effects-monitor.sh` na
          baterii, a throttle termiczny ma działać NIEZALEŻNIE od zasilania (to bezpieczeństwo
          sprzętu, nie kosmetyka). Wzorzec: jak `nightlight` – samodzielny toggle w
          `~/.config/mango-effects.conf`, komentarz = wyłączone, czytany bezpośrednio przez
          komponent QML (nowy `ThermalThrottle.qml` czytający plik, analogicznie do
          `WpmBorder.qml`/`~/.config/wpm-effects`), + nowa nazwa w `effects-ctl.sh`
          (`effects cpu-throttle on|off`).
        – Histereza: trzymać ograniczenie do max_perf_pct≈50% dopóki temp nie spadnie ≤ 70°C,
          potem przywrócić WARTOŚĆ ZAPAMIĘTANĄ przed throttle (nie na sztywno 100 – TLP/user
          mogą mieć tam coś innego).
        – **Uprawnienia do zapisu sysfs** (pasek działa jako user `iczo`, nie root): zapis do
          `max_perf_pct` wymaga roota. Kierunek: reguła udev/`systemd.tmpfiles.rules` dająca
          zapis na ten KONKRETNY atrybut sysfs (wzorzec już używany w projekcie dla
          v4l2loopback/Linksy – węższe i bezpieczniejsze niż sudoers NOPASSWD). Do ustalenia
          przy implementacji: udev rule na `SUBSYSTEM=="cpu"` vs `systemd.tmpfiles.rules`
          (`z /sys/devices/system/cpu/intel_pstate/max_perf_pct 0664 root iczo - -`).
        – Konflikt z TLP: TLP ma `CPU_MAX_PERF_ON_AC`/`_BAT`, który pisze do tego samego pliku –
          sprawdzić `/etc/tlp.conf`/`services.tlp` w `services.nix` i jeśli ustawione, wyłączyć
          albo zostawić komentarz ostrzegawczy.
        – Pułapki z researchu: zapamiętać `max_perf_pct` PRZED pierwszym throttle (nie zgadywać
          "był 100"), logować aktywacje (do oceny progów 85/70°C na tej maszynie).
        – Priorytet: **P2** (bezpieczeństwo termiczne, nie blokuje innych zadań – X250 ma już
          throttled+TLP+turbo-off-przy-buildzie jako warstwy ochrony).

---

## Pominięte

- [-] **CpDev / TwinCAD 3 / CodeSys 3** – Wine + zawasowane sterowniki na X250 to zabójcze. Brak sensu.

---

## Zaległe do zrobienia przez użytkownika (rebuild + weryfikacja)

Zmiany poniżej są w repo (working tree), ale część nigdy nie przeszła przez `./rebuild.sh`
(agent nie ma sudo w tej sesji – robi to zawsze użytkownik). Jeśli coś z tego już zostało
zrobione/zweryfikowane, po prostu usuń tę linię.

- [ ] **T2.40 (2026-11-20)**: bezpiecznik termiczny CPU w Quickshell (`ThermalThrottle.qml`)
      + `effects cpu-throttle [on|off]` + `systemd.tmpfiles.rules` w `services.nix` dający
      userowi `iczo` zapis do `max_perf_pct` bez sudo. `./rebuild.sh "T2.40: bezpiecznik
      termiczny CPU w Quickshell + effects cpu-throttle + tmpfiles max_perf_pct"`, potem
      **restart** (tmpfiles.rules stosowane są przy boocie – samo `nixos-rebuild switch` bez
      restartu może nie wystarczyć) i bezpieczny restart baru (`qs-launcher.sh`/SUPER+F11,
      NIE gołe `qs -c bar` z terminala Claude). Do zweryfikowania przez użytkownika (agent
      NIE mógł tego sprawdzić – brak sudo, zero dotykania żywego systemu w tej sesji):
      - `effects status` pokazuje linię `cpu-throttle: on (...)`,
      - `effects cpu-throttle off` i `effects cpu-throttle on` faktycznie przełączają (sprawdzić
        `cat ~/.config/mango-effects` – linia `cpu-throttle=off`/`on`),
      - po rebuildzie i restarcie: `cat /sys/devices/system/cpu/intel_pstate/max_perf_pct`
        i spróbować zwykłym userem (bez sudo) `echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct`
        – powinno się udać (plik własność `iczo`),
      - realny test throttle (obciążenie CPU do ~85°C, np. `stress-ng` albo długi build) –
        sprawdzić w `journalctl -t thermal-throttle` komunikaty aktywacji/dezaktywacji i że
        `max_perf_pct` faktycznie spada do 50 i wraca po ostygnięciu do ≤70°C,
      - sprawdzić czy TLP nie "odbija" ustawienia przy przełączaniu AC/bateria (patrz
        komentarz w `services.nix` przy `services.tlp` – możliwy konflikt, nieprzetestowany).

- [ ] **2026-11-20**: usunięto martwe pliki starego flake'owego configu (`flake.nix`,
      `flake.lock`, `home.nix`, `hosts/`) – naprawia alias `update`/`update-boot`
      (`nixos-rebuild-ng` wykrywał `/etc/nixos/flake.nix` i ignorował `-I nixos-config=...`).
      `./rebuild.sh "usunięcie martwych plików flake – naprawa update"`, potem sprawdzić
      że `update` i `update-boot` działają bez błędu o `hosts/laptop/hardware-configuration.nix`.
- [ ] Sesja 9 (2026-11-16): tty login (greetd off, auto `exec mango` w login shellu) +
      wlogout pod SUPER+Escape (przycisk Lock → hyprlock) + CHIRP. Po rebuildzie+restarcie
      sprawdzić: tty1 login prompt, login → Mango auto, SUPER+Escape → wlogout, Lock działa,
      Logout wraca do tty1, `chirp` widzi USB-serial.
- [ ] Sesja 10 (2026-11-16): fix `dotfiles/mango/config.conf` (błąd parsowania linia 52) +
      fix crasha Discorda (`localModulesRoot` w `build_info.json`). Po rebuildzie: Discord
      powinien normalnie wstawać.
- [ ] Sesja 11–12 (2026-11-19): scalenie efektów Quickshell do `dotfiles/quickshell/bar/`
      (Particles/WpmBorder/Shortcuts/TypingGlow przeniesione, martwe duplikaty w korzeniu
      usunięte), `effects-ctl.sh` przepisany (plik `~/.config/mango-effects.conf`,
      komentarz=wyłączone, + `pfx`/power-fx, + `nightlight`/wlsunset), `battery-effects-monitor.sh`
      nowy, `qs()` w shell.nix naprawione, particles – wiele motywów naraz (nie "ostatni
      wygrywa"), bindy SUPER+F5/F6/F7/F8 i SUPER+SHIFT+A (satty) dodane, SUPER+F6 → `effects edit`,
      fix symlinku `~/wpps` (tapety, `L+` + `find -L`), `autobright` → `brightnessctl`.
      Po rebuildzie i **bezpiecznym restarcie baru** (`qs-launcher.sh` / SUPER+F11 / nowe
      logowanie – NIE gołe `qs -c bar` z terminala agenta) sprawdzić: SUPER+F11, SUPER+F5/F7/F8,
      SUPER+SHIFT+A, SUPER+F10 (18 tapet), jasność klawiszami multimedialnymi, `effects status`,
      `effects particles-leaves on` + `effects particles-snow on` (oba naraz), SUPER+F6 otwiera
      edytor `mango-effects.conf`, odłączenie/podłączenie zasilacza (efekty gasną/wracają).
- [ ] Sesja 8 dogrywka (2026-11-16): Webots – fix `QT_QPA_PLATFORM` (wayland domyślnie,
      nadpisywalny) na crash "no Qt platform plugin". Po rebuildzie: `webots` startuje, otwiera
      `khepera3.wbt`, `from controller import Robot` działa bez ręcznego `WEBOTS_HOME`.

Pozostało (2026-11-21):
- `tts-mako.nix` zaimportowany w `configuration_minimal.nix`, ale binarek jeszcze nie ma na
  żywym systemie (generacja nie doszła) – do sprawdzenia po najbliższym pełnym rebuildzie.

Zrobione przy porządkach po incydencie z kartą SD/Syncthing (2026-11-20/21):
- `README.md` przywrócony z `origin/main` ("nixos-merged") – był nieaktualny po nadpisaniu.
- Martwa duplikacja `dotfiles/scripts/bgm-power-monitor.sh` usunięta (nieśledzona, bez żadnej
  referencji w mango/quickshell/shell.nix) – żywa wersja jest w `dotfiles/hypr/`.
- `download/qinst-lite-linux-25.1std-1129.run` (Quartus) nie istnieje na tej maszynie – nic do
  zrobienia tutaj, sprawdzić na maszynie, na której faktycznie leży (patrz BROKEN.md).
- `auto.sh` dostał guard przed ponownym nadpisaniem repo z zewnątrz (zmartwychwstałe martwe
  pliki = twardy stop, CRLF w `.sh` = ostrzeżenie, aktywny folder Syncthing = ostrzeżenie).

---

## G1-Prz-Controll na NixOS

**Postęp 2026-11-18:** dowiązania `~/Unitree/unitree_mujoco`, `~/unitree_sdk2` i
`~/unitree_sdk2_python` już wskazują na właściwe checkouty. `.venv` projektu ma
`include-system-site-packages = true`, a importy Tkinter/NumPy/Pillow/Paramiko/scp/pygame
działają. Konfiguracja NixOS została uzupełniona o brakujące zależności; pełny build
systemu pozostaje do wykonania przez `./rebuild.sh`.

- **MuJoCo:** checkout `/dane/sync/Dane/projekty/unitree_mujoco` zawiera model
  `unitree_robots/g1/g1_29dof.xml`, ale nie ma katalogu `venv`; lokalny podgląd wymaga
  przygotowania środowiska MuJoCo albo jawnego wskazania go przez `G1PRZ_MUJOCO_SITE_PACKAGES`.

- Utrzymywać dowiązania zgodności do checkoutów Unitree: `~/Unitree/unitree_mujoco` -> `/dane/sync/Dane/projekty/unitree_mujoco`, `~/unitree_sdk2` -> `/dane/sync/Dane/projekty/unitree_sdk2`, `~/unitree_sdk2_python` -> `/dane/sync/Dane/projekty/unitree_sdk2_python`. Są używane przez domyślne ścieżki aplikacji i narzędzi; nie kopiować ani nie modyfikować repozytoriów SDK.
- Dodać do konfiguracji NixOS Python 3 z Tkinterem i pakietami `paramiko`, `scp`, `pygame`, `pillow`, `numpy`; dodać `ffmpeg` (zapewnia `ffmpeg` i `ffprobe`) oraz dostęp do dźwięku przez PipeWire/PulseAudio i `pactl`.
- Sprawdzić lokalnie MuJoCo z `unitree_mujoco/venv`; opcjonalny podgląd nagrań wymaga pakietu `mujoco` oraz modelu `unitree_robots/g1/g1_29dof.xml`.
- Aplikację operatorską uruchamiać z katalogu repozytorium poleceniem `python3 frontend/main_app.py`; sam projekt pozostaje bez zmian.
- Konfiguracja już dostarcza `numpy`, `pillow` i Tkinter przez Nixowy `python3`; nie instalować `numpy` ani `pillow` przez pip (koło NumPy z PyPI wymagało brakującego `libstdc++.so.6`). Dla `.venv` w tym repo włączyć `include-system-site-packages = true` w `.venv/pyvenv.cfg`, usunąć z venv ewentualne kopie `numpy`/`pillow` instalowane pipem, a pozostałe `paramiko`, `scp`, `pygame` doinstalować przez pip. Aktywować `.venv` i uruchamiać `python3 frontend/main_app.py`.

**Aktualizacja 2026-11-18:** profil full udostępnia `ros2-humble` z przypiętego
nix-ros-overlay (ROS 2 Humble, ros-base, CycloneDDS, colcon i RViz), a także
Podman/Distrobox i porty UDP 7400–7500 dla DDS. Checkout `unitree_ros2` jest
zgodny z tym środowiskiem; jego skrypt `setup.sh` jest przeznaczony dla Foxy i
nie należy go używać w shellu Nixowym. Konfigurację Nix sprawdzono składniowo,
ale pełnego builda/aktywacji i testu połączenia z G1 nie wykonano: środowisko
sesji odrzuca `sudo` przez `no new privileges`. Pozostaje wdrożenie przez
`./rebuild.sh` na hoście z uprawnieniami administracyjnymi i weryfikacja DDS z
robotem.

---

## Nowy sprzęt NixOS — szybkie przygotowanie G1-Prz-Controll

Przed pierwszym uruchomieniem na nowej maszynie:

1. **Skonfiguruj pakiety systemowe w nix_conf:** w `python.nix` dodaj do `pythonWithAiRPackages` pakiety Python `paramiko`, `scp` i `pygame` (NumPy i Pillow są już deklarowane; Tkinter zapewnia używany tu Nixowy Python). Dodaj `ffmpeg` do pakietów systemowych. Włącz dźwięk PipeWire z kompatybilnością PulseAudio albo PulseAudio; sprawdź dostępność `pactl` oraz przynajmniej jednego odtwarzacza (`paplay`, `mpv` lub `ffplay`). Wykonaj rebuild systemu.
2. **Nie instaluj binarnych `numpy` ani `pillow` przez pip.** Na NixOS koło NumPy z PyPI może nie znaleźć `libstdc++.so.6`. Korzystaj z pakietów Nix. Jeśli projekt potrzebuje osobnego venv, utwórz go z `python3 -m venv --system-site-packages .venv`; to zachowuje widoczność `_tkinter`, NumPy i Pillow z Nix. Pozostałe biblioteki instaluj do tego venv.
3. **Umieść checkouty Unitree w stałych lokalizacjach** albo zaktualizuj poniższe cele dowiązań: `~/unitree_sdk2` -> checkout `unitree_sdk2`, `~/unitree_sdk2_python` -> checkout `unitree_sdk2_python`, `~/Unitree/unitree_mujoco` -> checkout `unitree_mujoco`. Repozytoriów nie kopiuj do projektu ani nie modyfikuj. Dla MuJoCo ustaw przy uruchomieniu `G1PRZ_MUJOCO_ROOT="$HOME/Unitree/unitree_mujoco"`, jeśli domyślna ścieżka względna nie pasuje do układu katalogów nowej maszyny.
4. **Sklonuj projekt i sprawdź środowisko** z jego katalogu:

   ```bash
   python3 -c 'import tkinter, _tkinter, numpy, PIL, paramiko, scp, pygame; print("zależności OK")'
   command -v ffmpeg ffprobe pactl
   python3 frontend/main_app.py
   ```

   Jeśli krok 1 dodał biblioteki do Nixowego `python3`, uruchamiaj nim projekt bez aktywnego venv. W innym przypadku aktywuj `.venv` przygotowany krokiem 2.
5. **Przed użyciem z robotem** ustaw jego adres (`G1PRZ_ROBOT_IP`) i skonfiguruj dostęp SSH kluczem. Najpierw sprawdź połączenie/status; żadnych testów ruchu nie wykonuj bez nadzoru i fizycznego zatrzymania pod ręką.
