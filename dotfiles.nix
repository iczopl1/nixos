# Dodatkowe symlinki dotfiles (systemd-tmpfiles). Aliasy i funkcje bash są w shell.nix.
{ ... }:

let
  # Ścieżka do folderu dotfiles OBOK tego pliku (np. /etc/nixos/dotfiles).
  # toString nie kopiuje do /nix/store, więc pliki zostają edytowalne
  # (np. nvim może zapisywać lazy-lock.json, jeśli masz prawa zapisu).
  dotfiles = toString ./dotfiles;
in
{
  # Pulpit Mango/Quickshell i jego skrypty są linkowane w shell.nix.
  systemd.user.tmpfiles.users.iczo.rules = [
    # Tapety: ~/wpps → dotfiles/wallpapers – tu (nie w ~/.config/wallpapers) szukają
    # switch-random-wallpaper.sh, wallhaven-wallpaper.sh, wal-apply-theme.sh i
    # rofi-wallpaper-switcher.sh (SUPER+F10 bar menu). "L+" (nie "L"): bez tego systemd-tmpfiles
    # nigdy nie aktualizuje już istniejącego symlinka, więc po przeniesieniu repo (np.
    # ~/nix_conf -> ten katalog) link zostawał wskazujący na starą, nieistniejącą ścieżkę
    # i SUPER+F10 pokazywał puste menu – to właśnie się stało tutaj.
    "L+ %h/wpps - - - - ${dotfiles}/wallpapers"
    # Mako: powiadomienia – timeout 5 s (domyślnie 0 = zostają na zawsze)
    "d %h/.config/mako 0755 - - -"
    "L+ %h/.config/mako/config - - - - ${dotfiles}/mako/config"
    # wlogout (SUPER+Escape, config.conf): tylko layout – "lock" woła hyprlock bezpośrednio
    # (loginctl lock-session nie ma w Mango nic, co by go obsłużyło). style.css NIE linkowany
    # celowo – pakiet ma własny domyślny style.css z ikonami wskazującymi na jego własną
    # ścieżkę w /nix/store, zawsze zgodną z zainstalowaną wersją (bez ryzyka złego hasha po
    # aktualizacji wlogout, gdyby skopiować style.css ze starej wersji).
    "d %h/.config/wlogout 0755 - - -"
    "L+ %h/.config/wlogout/layout - - - - ${dotfiles}/wlogout/layout"
  ];
}
