# Programy dla profilu minimal.
# Wymóg: GUI (Mango+Quickshell), nvim, przeglądarka, KeePass, Claude Code, terminal, git.
# Bez ciężkiej kompilacji – wszystko z cache nixpkgs (MASTER §4).
{ pkgs, lib, ... }:

let
  # Biblioteki uruchomieniowe dla binarek spoza Nix (claude-code i inne).
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glib
    dbus
    fontconfig
    freetype
    libGL
    libx11
    libxext
    libxrender
    libxcb
    libxcb-util
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-wm
    libxkbcommon
    wayland
  ];
in
{
  environment.systemPackages = with pkgs; [
    # --- Pulpit Wayland (Mango) ---
    quickshell            # pasek + nakładka Hints.qml (z nixpkgs, bez kompilacji – MASTER §12)
    alacritty             # terminal główny
    foot                  # terminal zapasowy
    rofi                  # launcher
    grim
    slurp
    wl-clipboard
    cliphist
    awww                  # tapety (swww przemianowany na awww w nixpkgs 26.05)
    mako                  # powiadomienia
    brightnessctl
    pavucontrol
    networkmanagerapplet
    wvkbd                 # klawiatura ekranowa (tablet/touch)
    yad                   # dialogi GUI dla skryptów
    udiskie               # auto-mount USB/dysków (frontend dla udisks2)
    wlopm                 # wyłączanie ekranu przez wlr-output-power-management (T2.5)

    # --- Diagnostyka dysków (T2.2) ---
    smartmontools         # smartctl / smartd – SMART monitoring HDD/SSD/NVMe
    nvme-cli              # nvme – narzędzia dla dysków NVMe
    hdparm                # hdparm – parametry i wydajność dysków ATA/SATA

    # --- Narzędzia sieciowe (T2.3) ---
    nmap                  # skanowanie portów i sieci
    iperf3                # pomiar przepustowości
    bandwhich             # prędkość sieci per-proces w terminalu
    dnsutils              # dig, nslookup – zapytania DNS
    tcpdump               # przechwytywanie pakietów (wymaga sudo)
    nethogs               # ruch sieciowy per-proces (wymaga sudo)
    speedtest-cli         # pomiar prędkości łącza

    # --- Narzędzia terminalowe ---
    jq
    fzf
    zoxide
    btop
    socat
    ripgrep
    procps
    gawk
    coreutils
    wget
    curl
    git
    p7zip
    tree
    fastfetch
    mpv

    # --- Przeglądarka ---
    # brave – usunięty z nixpkgs 26.05 (brak maintainerów); TODO: binarka z oficjalnych Releases
    firefox

    # --- Edytory ---
    neovim

    # --- AI: zasada najważniejsza (MASTER §0/§16) ---
    claude-code

    # --- nvim: LSP, formattery, narzędzia ---
    lua-language-server
    stylua
    nixfmt              # formater .nix (T2.13; nixfmt-rfc-style → nixfmt od 26.05)
    hunspell
    hunspellDicts.en_US
    hunspellDicts.pl_PL
    zathura               # podgląd PDF (vimtex)
    glow                  # podgląd Markdown (:Glow)
    imagemagick

    # --- Hasła ---
    keepassxc

    # --- Podstawowy toolchain (MASTER §4) ---
    gcc
    gnumake
    cmake
    python3
  ] ++ runtimeLibs;

  # Blokada ekranu (pakiet + usługa PAM)
  programs.hyprlock.enable = true;

  # Menedżer plików
  programs.thunar.enable = true;
  programs.xfconf.enable = true;

  # Diagnostyka sieci (setuid wrapper dla ICMP ping bez root)
  programs.mtr.enable = true;

  # GPG / SSH agent
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Binarki spoza Nix (claude-code i inne niestandardowe)
  programs.nix-ld.enable = true;

  # GTK / dconf (Thunar, ustawienia motywu GTK)
  programs.dconf.enable = true;

  # uinput – potrzebny przez ydotool (keyboard-mouse.nix w full) i OpenTabletDriver
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_SESSION_TYPE = "wayland";
  };
}
