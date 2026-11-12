# Dodatkowe symlinki dotfiles (systemd-tmpfiles). Aliasy i funkcje bash są w shell.nix.
{ ... }:

let
  # Ścieżka do folderu dotfiles OBOK tego pliku (np. /etc/nixos/dotfiles).
  # toString nie kopiuje do /nix/store, więc pliki zostają edytowalne
  # (np. nvim może zapisywać lazy-lock.json, jeśli masz prawa zapisu).
  dotfiles = toString ./dotfiles;
in
{
  # Typ "L" tworzy link tylko gdy celu jeszcze nie ma - jeśli masz już np.
  # ~/.config/nvim, usuń/przenieś go i zaloguj się ponownie
  # (albo: systemctl --user restart systemd-tmpfiles-setup).
  # Z ~/.config/hypr linkowany jest tylko hyprlock.conf (domyślna ścieżka hyprlocka);
  # reszta konfiguracji Hyprlanda usunięta.
  # Konfiguracja Mango (~/.config/mango) i quickshell - patrz SETUP.md.
  systemd.user.tmpfiles.users.iczo.rules = [
    "d %h/.config/hypr 0755 - - -"
    "L %h/.config/hypr/hyprlock.conf - - - - ${dotfiles}/hyprlock/hyprlock.conf"
    # T3.7: skrypty statusu telefonu i przełącznika BT
    "d %h/.config/scripts 0755 - - -"
    "L+ %h/.config/scripts/phone-status.sh - - - - ${dotfiles}/scripts/phone-status.sh"
    "L+ %h/.config/scripts/bt-headset.sh   - - - - ${dotfiles}/scripts/bt-headset.sh"
    # Tapety: ~/.config/wallpapers → dotfiles/wallpapers (switch-random-wallpaper.sh szuka tu)
    "L %h/.config/wallpapers - - - - ${dotfiles}/wallpapers"
    # Mango: config linkowany z repo (bez tego zmiany w repo nie trafiają do kompozytora)
    "d %h/.config/mango 0755 - - -"
    "L+ %h/.config/mango/config.conf - - - - ${dotfiles}/mango/config.conf"
    # Mako: powiadomienia – timeout 5 s (domyślnie 0 = zostają na zawsze)
    "d %h/.config/mako 0755 - - -"
    "L+ %h/.config/mako/config - - - - ${dotfiles}/mako/config"
  ];
}
