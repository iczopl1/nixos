# Konfiguracja NixOS 25.11 (klasyczna: bez flake'ów, bez home-managera).
# Sesja graficzna: Mango. Pasek: Quickshell.
# Instalacja: ./rebuild.sh "opis"  lub skopiuj folder do /etc/nixos/.
{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./unstable.nix        # argument `unstable` dla mango.nix i keyboard-mouse.nix
    ./mango.nix           # kompozytor Mango + portale + wpis sesji
    ./keyboard-mouse.nix  # wl-kbptr, hintd, ydotool, Signal/Ferdium z a11y
    ./ros2.nix            # podman, distrobox, porty DDS
    ./tailnet-b.nix       # druga sieć Tailscale w namespace
    ./crafts.nix          # aplikacje Craft (budowane ze źródeł, długi pierwszy build)
    # ./clev.nix          # NIE importować: brak źródeł ./hintdrive (patrz SETUP.md)
    ./security.nix        # SSH off, firewall, otwarte porty
    ./system.nix          # boot, sieć, locale, użytkownik, bluetooth, libvirt
    ./services.nix        # greetd -> mango, pipewire, tailscale (tailnet A), syncthing
    ./power.nix           # usypia tylko przycisk zasilania; klapa/bezczynność nic nie robią
    ./programs.nix        # programy systemowe
    ./python.nix          # Python 3.13 + pakiety naukowe, pyenv
    ./fonts.nix           # czcionki
    ./shell.nix           # bash aliasy/funkcje, fzf, zoxide, symlinki dotfiles
    ./dotfiles.nix        # symlinki (hyprlock)
    ./tts-mako.nix        # moduł TTS dla powiadomień mako (domyślnie wyłączony)
  # /etc/nixos/local.nix – ustawienia per-maszyna (dysk /dane, cpuTarget, efekty) – poza repo.
  ] ++ lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;

  # Unfree tylko dla konkretnych pakietów (MASTER §16). Nie allowUnfree = true globalnie.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (builtins.parseDrvName pkg.name).name [
      "claude-code"           # MASTER §0/§16 – zasada najważniejsza
      "claude-code-bin"
      "brave"
      "google-chrome"
      "discord"
      "anydesk"
      "android-studio"
      "android-studio-stable"
      "gemini-cli"
      "maltego"
    ];
}
