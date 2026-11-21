# Usługi: logowanie w TTY (bez greetd), PipeWire, Tailscale (tailnet A), Syncthing.
{ config, pkgs, ... }:

{
  # Moduł z tts-mako.nix; włącz na true, jeśli chcesz czytanie powiadomień.
  services.ttsMako.enable = false;

  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  # Logowanie przez standardowy getty na tty1 (bez greetd/autologin) – przy starcie
  # systemu widać login/password prompt w konsoli. Mango startuje automatycznie
  # dopiero PO zalogowaniu (shell.nix, programs.bash.loginShellInit) – klasyczny
  # wzorzec "exec startx" z .bash_profile. Wylogowanie z Mango (przez wlogout,
  # SUPER+... – programs_minimal.nix) wraca do tego samego login prompta na tty1.
  services.greetd.enable = false;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    wireplumber.enable = true;
  };

  # Realtime priority dla wątków PipeWire/WirePlumber (polecane w dokumentacji PipeWire).
  # Bez tego pod obciążeniem CPU (np. odbiór strumienia Moonlight – dekodowanie wideo VAAPI
  # + dekodowanie audio Opus w moonlight-qt) wątek audio może zostać wywłaszczony przez
  # scheduler, co słyszalne jest jako okresowe trzaski/wycinki – "co chwilę", nie co ramkę.
  security.rtkit.enable = true;

  # Tailscale = tailnet A (tailscale0). tailnet-b.nix uruchamia obok drugi demon.
  services.tailscale.enable = true;

  # udisks2 – D-Bus daemon do zarządzania dyskami; wymagany przez udiskie (auto-mount USB).
  services.udisks2.enable = true;

  # Syncthing - synchronizacja z telefonem i PC.
  # Porty otwarte jawnie w security.nix (nie openDefaultPorts).
  services.syncthing = {
    enable = true;
    user = "iczo";
    dataDir = "/home/iczo";
    configDir = "/home/iczo/.config/syncthing";
    guiAddress = "127.0.0.1:8384";
  };

  # T2.4: Drukarka HP LaserJet M175n (USB, auto-wykrycie przez CUPS + hplip).
  # Avahi wykrywa drukarki w sieci lokalnej (mdns); mDNS wymagany przez CUPS Bonjour.
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;        # host discovery (.local) w /etc/nsswitch.conf
    openFirewall = true;    # port 5353/udp dla mDNS (sieć lokalna, nie internet)
  };

  # AT-SPI2 accessibility bus – wymagany przez hintd (Super+D hints) do wykrywania
  # klikalnych elementów w GTK/Qt i innych aplikacjach przez D-Bus accessibility API.
  services.gnome.at-spi2-core.enable = true;

  # T1.15: throttled (lenovo-throttling-fix) – naprawia BIOS-owe dławienie CPU na X250.
  # BIOS ustawia PL1=15W / PL2=25W i co ~28s resetuje limity mocy do minimalnych,
  # powodując regularne "dropy" wydajności. throttled przywraca pełne PL1/PL2.
  services.throttled.enable = true;

  # T1.14: TLP – zarządzanie energią laptopa + progi ładowania baterii ThinkPad X250.
  # START=40 / STOP=80: ładuje od 40% do 80% → ogniwo rzadziej w ekstremalnych SoC,
  # co znacząco wydłuża jego żywotność (badania Lenovo: 3× więcej cykli niż 0–100%).
  # TLP nadpisuje power-profiles-daemon; obie usługi nie mogą działać jednocześnie.
  #
  # UWAGA (T2.40): poniższe ustawienia NIE definiują CPU_MAX_PERF_ON_AC/CPU_MAX_PERF_ON_BAT
  # (tylko CPU_SCALING_GOVERNOR i CPU_BOOST), więc na dziś TLP nie nadpisuje jawnie
  # `max_perf_pct`. Ale TLP samo w sobie zarządza tym plikiem przy każdej zmianie
  # źródła zasilania (AC<->bateria) i może go tam resetować niezależnie od naszego
  # bezpiecznika termicznego (dotfiles/quickshell/bar/ThermalThrottle.qml, patrz niżej
  # systemd.tmpfiles.rules) – DWA mechanizmy piszące do tego samego pliku. Jeśli po
  # rebuildzie throttle będzie "migać" (włącza się i od razu wraca do 100%) przy
  # przełączaniu AC/bateria, to będzie ten konflikt – NIE wyłączać TLP bez pytania
  # użytkownika, tylko zgłosić.
  services.power-profiles-daemon.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      # Progi ładowania dla BAT0 (główna) i BAT1 (jeśli jest slice battery)
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0  = 80;
      START_CHARGE_THRESH_BAT1 = 40;
      STOP_CHARGE_THRESH_BAT1  = 80;

      # CPU na zasilaniu sieciowym – pozwól na turbo (rebuild.sh go i tak wyłącza podczas buildu)
      CPU_SCALING_GOVERNOR_ON_AC  = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_BOOST_ON_AC  = 1;
      CPU_BOOST_ON_BAT = 0;

      # Dysk: APM + czas wyciszenia (oszczędność energii na baterii)
      DISK_APM_LEVEL_ON_BAT  = "128";
      DISK_IOSCHED_ON_BAT    = "mq-deadline";

      # WiFi – nie wyłączaj po hibernacji
      WIFI_PWR_ON_AC  = "off";
      WIFI_PWR_ON_BAT = "on";
    };
  };

  # T2.40: bezpiecznik termiczny CPU (85°C -> max_perf_pct 50%, histereza do 70°C) żyje
  # w Quickshell (dotfiles/quickshell/bar/ThermalThrottle.qml), jako zwykły user (iczo),
  # bez sudo – więc ten plik musi być zapisywalny przez usera, nie tylko przez root.
  #
  # `z` (nie `f`/`Z`): zmienia właściciela/uprawnienia TYLKO JEŚLI plik już istnieje;
  # nic nie tworzy i nie usuwa. Na maszynie bez sterownika intel_pstate (inny CPU, inny
  # governor) ta ścieżka po prostu nie istnieje – reguła jest wtedy no-opem, więc jest
  # bezpieczna do trzymania w tym (wspólnym dla minimal i full) pliku na każdej maszynie,
  # nie tylko X250. Zgodnie z MASTER §0 złotą regułą 7 (bez flake'ów/warunkowania przez
  # hosty) nie rozróżniamy tu maszyn w Nixie – samo zmienienie uprawnień pliku niczego
  # nie włącza (to robi dopiero ThermalThrottle.qml, i to tylko gdy `effects cpu-throttle`
  # jest ON, patrz effects-ctl.sh).
  #
  # Wybór tmpfiles (nie udev rule): max_perf_pct nie jest urządzeniem (nie ma eventu
  # "add"/"change" w udev do zahaczenia reguły) – to płaski atrybut sysfs wystawiany przez
  # sterownik intel_pstate przy starcie kernela, obecny już w momencie, gdy
  # systemd-tmpfiles-setup.service biegnie przy boocie (sysfs montowany dużo wcześniej).
  # `systemd.tmpfiles.rules` jest więc prostszym i bardziej bezpośrednim mechanizmem niż
  # pisanie reguły udev tylko po to, by też w praktyce odpalić `chmod`/`chown` raz przy starcie.
  #
  # Właściciel: użytkownik "iczo" wprost (nie grupa) – isNormalUser w nixos-base.nix nie
  # definiuje osobnej grupy "iczo" (domyślna grupa to "users"), a na tej maszynie
  # jednoosobowej to i tak jedyny user, któremu ma zależeć na zapisie tutaj.
  systemd.tmpfiles.rules = [
    "z /sys/devices/system/cpu/intel_pstate/max_perf_pct 0644 iczo root - -"
  ];
}
