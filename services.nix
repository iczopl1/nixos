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
}
