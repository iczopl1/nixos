# Programy systemowe. Mango, keyboard-mouse, ros2 i crafts mają własne moduły.
# hyprlock zostaje jako blokada ekranu (działa w Mango).
{ config, pkgs, lib, ... }:

let
  # Biblioteki uruchomieniowe dla binarek spoza Nix
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glib
    dbus
    fontconfig
    freetype
    libGL
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libxcb
    xorg.xcbutil
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    libxkbcommon
    wayland
  ];
in
{
  environment.systemPackages = with pkgs; [
    # --- Pulpit Wayland (Mango) ---
    quickshell            # pasek + nakładka podpowiedzi SUPER+D (Hints.qml)
    alacritty
    foot
    kitty
    waybar
    rofi
    wofi
    grim
    slurp
    wl-clipboard
    cliphist
    swww
    mako
    dunst
    brightnessctl
    pavucontrol
    networkmanagerapplet
    wvkbd                 # klawiatura ekranowa
    yad
    ydotool
    glava
    eww
    pywal
    # Blokada ekranu: hyprlock -> programs.hyprlock niżej (pakiet + PAM)

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
    mpc
    mpv
    cava

    # --- Przeglądarki / komunikacja ---
    brave
    google-chrome
    discord
    anydesk

    # --- Edytory / IDE ---
    neovim
    vscodium
    android-studio
    android-tools
    flutter
    mesa-demos            # eglinfo

    # --- Programowanie ---
    gcc
    (lib.lowPrio clang)   # lowPrio: `cc` zostaje z gcc
    clang-tools
    cmake
    ninja
    gnumake
    gdb
    lldb
    jdk17                 # JAVA_HOME (Android/Flutter)
    (lib.lowPrio jdk21)   # dostępny, ale `java` = jdk17
    maven
    gradle
    kotlin
    go
    nodejs
    yarn
    prettier
    eslint
    markdownlint-cli
    grip

    # --- AI ---
    # Claude Code – zasada najważniejsza (MASTER §0/§16): musi być dostępny zawsze.
    # Gotowa binarka z nixpkgs, bez kompilacji.
    claude-code
    gemini-cli

    # --- Biuro / grafika / dokumenty ---
    libreoffice-fresh
    gimp
    krita
    texliveFull
    texlab
    pandoc
    graphviz
    imagemagick
    hunspell
    hunspellDicts.en_US
    hunspellDicts.pl_PL

    # --- Neovim: LSP, formatery, narzędzia (zamiast Masona) ---
    # Pozostałe używane przez nvim: clang-tools (clangd, clang-format), lldb (lldb-dap),
    # texlab, pyright + black + debugpy (python.nix), texliveFull (latexmk).
    lua-language-server
    stylua
    google-java-format
    java-language-server
    zathura               # podgląd PDF dla vimtex
    glow                  # podgląd Markdown (:Glow)

    # --- Hasła ---
    keepassxc

    # --- Gry ---
    prismlauncher

    # --- Bezpieczeństwo ---
    maltego
  ] ++ runtimeLibs;

  # OpenTabletDriver
  hardware.opentabletdriver.enable = true;
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" ];

  # Blokada ekranu. Opcja instaluje hyprlock i dodaje usługę PAM (bez niej hasło nie przejdzie).
  # Konfiguracja: dotfiles/hyprlock/hyprlock.conf - kropka na każdy wpisany znak.
  programs.hyprlock.enable = true;

  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Binarki typu adb z SDK
  programs.nix-ld.enable = true;

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XDG_SESSION_TYPE = "wayland";
  };

  environment.variables = {
    JAVA_HOME = "${pkgs.jdk17}";
    CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome";
  };
}
