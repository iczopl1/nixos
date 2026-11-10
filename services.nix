# Usługi ze starej konfiguracji (modules/services/default.nix), sesja zmieniona na Mango.
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

  # Syncthing - synchronizacja z telefonem i PC
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "iczo";
    guiAddress = "127.0.0.1:8384";
  };
}
