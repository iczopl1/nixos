# Czcionki systemowe. Barlow (etykiety hintd) dodaje keyboard-mouse.nix.
{ pkgs, ... }:

{
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
      nerd-fonts.symbols-only
      noto-fonts
      noto-fonts-color-emoji
    ];
  };
}
