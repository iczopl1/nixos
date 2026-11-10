# Scalona konfiguracja NixOS 25.11 (klasyczna: bez flake'ów, bez home-managera).
# Baza: nixos-selected (ma pierwszeństwo). Dołożone: programy, usługi i ustawienia
# ze starej konfiguracji `nixos` (flake + home-manager), bez Hyprlanda (sesja = Mango).
#
# Instalacja: skopiuj CAŁY ten folder do /etc/nixos/ i `sudo nixos-rebuild switch`.
# Szczegóły: README.md i SETUP.md.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix

    # --- z nixos-selected (bez zmian) ---
    ./unstable.nix        # argument `unstable` dla mango.nix i keyboard-mouse.nix
    ./mango.nix           # kompozytor Mango + portale + wpis sesji
    ./keyboard-mouse.nix  # wl-kbptr, hintd, ydotool, Signal/Ferdium z a11y
    ./ros2.nix            # podman, distrobox, porty DDS
    ./tailnet-b.nix       # druga sieć Tailscale w namespace
    ./crafts.nix          # aplikacje Craft (budowane ze źródeł, długi pierwszy build)
    # ./clev.nix          # NIE importować: brak źródeł ./hintdrive (patrz SETUP.md)

    # --- przeniesione ze starej konfiguracji ---
    ./system.nix          # boot, sieć, locale, użytkownik, bluetooth, libvirt
    ./services.nix        # greetd -> mango, pipewire, tailscale (tailnet A), syncthing
    ./power.nix           # usypia tylko przycisk zasilania; klapa/bezczynność nic nie robią
    ./programs.nix        # wszystkie programy z obu konfiguracji (bez Hyprlanda)
    ./python.nix          # Python 3.11 + pakiety naukowe, pyenv
    ./fonts.nix           # czcionki
    ./shell.nix           # bash aliasy/funkcje, fzf, zoxide, symlinki dotfiles
    ./dotfiles.nix        # dodatkowe symlinki (hyprlock)
    ./tts-mako.nix        # moduł TTS dla powiadomień mako (domyślnie wyłączony)
  ];

  nixpkgs.config.allowUnfree = true;
}
