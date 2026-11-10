{ pkgs, unstable, ... }:

# Mango compositor. Not in nixpkgs 25.11, so taken from unstable
# (uses the `unstable` arg exported by unstable.nix).
# Mirrors nixos-unstable's programs.mango module.
let
  # Adds tag_animation_slide_ratio / tag_animation_fade (Hyprland "slidefade 20%").
  # Defaults keep stock behaviour. Copy mango-tag-slidefade.patch next to this file.
  mango = unstable.mango.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mango-tag-slidefade.patch ];
  });
in
{
  environment.systemPackages = [ mango ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config.mango = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      "org.freedesktop.impl.portal.Inhibit" = [ "gtk" ];
    };
  };

  # Adds a "mango" entry for login managers
  services.displayManager.sessionPackages = [ mango ];
  systemd.services.iio-sensor-proxy.wantedBy = [ "multi-user.target" ];
}
