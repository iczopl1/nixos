# Dotfiles bez home-managera (nixos-selected nie używa HM).
# Symlinki tworzone przez systemd-tmpfiles użytkownika iczo.
# Komendy powłoki (aliasy/funkcje bash) celowo NIE są tu przenoszone ze starej
# konfiguracji - obowiązują tylko te z nixos-selected.
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
  ];
}
