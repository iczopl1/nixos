# Dev shell for bash-suggest on NixOS: `nix-shell` in this folder.
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  packages = with pkgs; [ rustc cargo gcc bashInteractive ];
}
