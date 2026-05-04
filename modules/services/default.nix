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

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}