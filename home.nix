{ config, pkgs, ... }:

{
  # You can add your Home Manager configurations here
  # For example:
  # home.packages = with pkgs; [
  #   firefox
  #   git
  # ];
  # Let Home Manager manage your dotfiles
  programs.home-manager.enable = true;

#do hyprlock niezbedne
  wayland.windowManager.hyprland.systemd.enable = false;
  home.stateVersion = "25.11"; # Please adjust to your NixOS version
}
