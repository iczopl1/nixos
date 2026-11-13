# Usługi: greetd+Mango, PipeWire, Tailscale (tailnet A), Syncthing.
{ config, pkgs, ... }:

{
  # Moduł z tts-mako.nix; włącz na true, jeśli chcesz czytanie powiadomień.
  services.ttsMako.enable = false;

  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  # Menedżer sesji: startuje od razu Mango jako iczo (wcześniej Hyprland).
  # Mango jest instalowany przez mango.nix (z łatką slidefade).
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "/run/current-system/sw/bin/mango";
      user = "iczo";
    };
  };
  # Alternatywa z ekranem logowania i wyborem sesji (mango.nix rejestruje sesję "mango"):
  # services.greetd.settings.default_session.command =
  #   "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    wireplumber.enable = true;
  };

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

  # T1.14: TLP – zarządzanie energią laptopa + progi ładowania baterii ThinkPad X250.
  # START=40 / STOP=80: ładuje od 40% do 80% → ogniwo rzadziej w ekstremalnych SoC,
  # co znacząco wydłuża jego żywotność (badania Lenovo: 3× więcej cykli niż 0–100%).
  # TLP nadpisuje power-profiles-daemon; obie usługi nie mogą działać jednocześnie.
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
}
