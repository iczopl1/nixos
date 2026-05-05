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
  openDefaultPorts = true; # Open ports in the firewall for Syncthing. (NOTE: this will not open syncthing gui port)
  user = "iczo";
};



  # Enable the OpenSSH daemon.

  #Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
