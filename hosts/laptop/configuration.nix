# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, self, ... }:

{
  imports = [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/programs/default.nix
      ../../modules/system/default.nix
      ../../modules/services/default.nix
    ]; # Add semicolon here






}
