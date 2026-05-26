{ config, pkgs, ... }:

{
  imports = [
    ./tts-mako.nix
  ];
#services.ttsMako.enable = true;
services.ttsMako.enable = false;
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


#tailscale ustawienia 
services.tailscale = {
    enable = true;
    # Enable tailscale at startup

    # If you would like to use a preauthorized key
    #authKeyFile = "/run/secrets/tailscale_key";

  };

#syncthing sync z telefonem i pc
services.syncthing = {
  enable = true;
  openDefaultPorts = true;
  user = "iczo";
  guiAddress = "127.0.0.1:8384";
};

#flatpak do niedziałających rzeczy


  # Enable the OpenSSH daemon.

  #Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
