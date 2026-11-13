# Profil minimal NixOS 25.11 (bez flake'ów, bez home-managera).
# Sesja graficzna: Mango. Pasek: Quickshell (z nixpkgs, bez kompilacji).
# Co musi działać: GUI, nvim, brave, KeePassXC, Claude Code, terminal, git, dźwięk.
# Instalacja: ./rebuild.sh "opis"  lub skopiuj folder do /etc/nixos/.
{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./unstable.nix        # argument `unstable` dla mango.nix i keyboard-mouse.nix
    ./mango.nix           # kompozytor Mango + portale + wpis sesji
    # keyboard-mouse.nix – tylko w full (kompiluje wl-kbptr i hintd)
    # tailnet-b.nix      – tylko w full (drugi Tailscale w namespace)
    ./security.nix        # SSH off, firewall, otwarte porty
    ./nixos-base.nix      # boot, sieć, locale, użytkownik, bluetooth, libvirt
    ./services.nix        # greetd -> mango, pipewire, tailscale (tailnet A), syncthing
    ./power.nix           # usypia tylko przycisk zasilania; klapa/bezczynność nic nie robią
    ./programs_minimal.nix  # programy profilu minimal
    ./fonts.nix           # czcionki
    ./shell.nix           # bash aliasy/funkcje, fzf, zoxide, symlinki dotfiles
    ./dotfiles.nix        # symlinki (hyprlock)
    ./tts-mako.nix        # moduł TTS dla powiadomień mako (domyślnie wyłączony)
    # /etc/nixos/local.nix – ustawienia per-maszyna (dysk /dane, cpuTarget) – poza repo
  ] ++ lib.optional (builtins.pathExists /etc/nixos/local.nix) /etc/nixos/local.nix;

  # Unfree tylko dla konkretnych pakietów (MASTER §16). Lista zawiera paczki z obu profili –
  # biała lista nie szkodzi, gdy pakiet nie jest zainstalowany.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"           # MASTER §0/§16 – zasada najważniejsza
      "claude-code-bin"
      "brave"
      "google-chrome"
      "discord"
      "discord-unwrapped"   # wewnętrzna nazwa paczki (nixpkgs owija discord-unwrapped)
      "anydesk"
      "android-studio"
      "android-studio-stable"
      "gemini-cli"
      "antigravity-cli"     # następca gemini-cli
      "maltego"
      "signal-desktop"        # keyboard-mouse.nix (full)
      "steam"
      "steam-unwrapped"
      "steam-run"
    ];
}
