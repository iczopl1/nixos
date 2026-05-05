{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
#terminal
   alacritty
#hyprland
   hyprlock
   waybar
   rofi
   grim
   brave
   mako
   dunst
   wl-clipboard
   wofi
   btop
# Hyprland related dependencies (from dotfiles analysis)
    cliphist
    swww
    hypridle
    glava
    foot
    kitty
# Additional Hyprland script dependencies
    pywal
    gawk
    coreutils
    eww
    mpv
    socat
    ripgrep
    procps


#Main programy
   neovim
   vscodium
   flutter
   android-tools
   wget
   cava
   discord
   python3
   python311Packages.pip
   python311Packages.virtualenv
#programer tools
   gcc
   gnumake
   gdb
   clang-tools
   git
   curl
   xdg-desktop-portal-hyprland
#chatyGPT AI TOOLS
  nodejs
  gemini-cli
# LibreOffice (pełny pakiet)
    libreoffice-fresh
# Grafika (paint + zaawansowane)
    gimp
    krita
#Gry 
    prismlauncher
# Nerd Fonts (cała kolekcja lub wybierz konkretne)
pkgs.nerd-fonts.fira-code
pkgs.nerd-fonts.jetbrains-mono
pkgs.nerd-fonts.hack
# LaTeX (pełny)
    texliveFull

# Dodatkowe narzędzia LaTeX
    texlab          # LSP do LaTeX
    pandoc          # konwersje
# Graphviz (grafy)
    graphviz

# Python + matplotlib (opcjonalnie do wykresów)
    python3Packages.matplotlib
# ImageMagick (obróbka obrazów w LaTeX/pandoc)
    imagemagick
#Hasełka 
    keepassxc
#słowniki do spellchceck
  hunspell
  hunspellDicts.en_US
  hunspellDicts.pl_PL
# Neovim dependencies (from dotfiles analysis)
    python3Packages.mypy
    python3Packages.black
    google-java-format
    stylua
    #vscode-html-languageserver
    #vscode-css-languageserver
    #python3Packages.pyright
    java-language-server
    #python3Packages.debugpy

#Terminal program
    p7zip
    tree
    fastfetch
  ];
  programs.thunar.enable = true;
  #hyprland
  programs.hyprland.enable = true;
  environment.sessionVariables = {
    NIXOS_OZONE_WL ="1";
    XDG_SESSION_TYPE = "wayland";
  };
  programs.xfconf.enable = true;

  programs.mtr.enable = true;
  programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
  };
 }
