{ config, pkgs, ... }:

{
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

#sesion manager
services.greetd.enable = true;

services.greetd.settings.default_session = {
command ="${pkgs.hyprland}/bin/Hyprland";
user = "iczo";
};

#pipewire audio control
services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    wireplumber.enable = true;
  };

  # Enable the OpenSSH daemon.

  #Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
