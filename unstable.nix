{ config, pkgs, ... }:

let
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {
    config = {
      allowUnfree = true;
    };
  };
in
{
  # Expose it so other modules can use it
  _module.args.unstable = unstable;
}
