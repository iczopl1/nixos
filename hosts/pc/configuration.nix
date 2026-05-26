# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glib
    dbus
    fontconfig
    freetype
    libGL
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libxcb
    xorg.xcbutil
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    libxkbcommon
    wayland
  ];
in


{
  imports = [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/programs/default.nix
      ../../modules/system/default.nix
      ../../modules/services/default.nix
];
  

  fonts = {
    fontDir.enable = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      fira-code
      fira-code-symbols
      font-awesome
      jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.symbols-only
    ];
  };

  environment.systemPackages = with pkgs; [
    python311
    gcc
  ] ++ runtimeLibs;

  environment.sessionVariables = {
  };
}
