{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
#terminal
   alacritty
#hyprland
   waybar
   rofi
   grim
   librewolf
   mako
   dunst
   wl-clipboard
   wofi
   btop
#Main programy
   neovim
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
#   gemini-cli
# LibreOffice (pełny pakiet)
    libreoffice-fresh
# Grafika (paint + zaawansowane)
    gimp
    krita
# Arduino IDE
#     arduino-ide

# KDE Connect
#	kdePackages.kdeconnect-kde
# Nerd Fonts (cała kolekcja lub wybierz konkretne)
#pkgs.nerd-fonts.fira-code
#pkgs.nerd-fonts.jetbrains-mono
#pkgs.nerd-fonts.hack
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

# Neovim dependencies (from dotfiles analysis)
    python3Packages.mypy
    python3Packages.black
    google-java-format
    stylua
    #vscode-html-languageserver
    #vscode-css-languageserver
    #python3Packages.pyright
    java-language-server
    python3Packages.debugpy

# Hyprland related dependencies (from dotfiles analysis)
    cliphist
    swww
    #hypridle
    glava
    foot
    kitty

# Additional Hyprland script dependencies
    #wal
    gawk
    coreutils
    eww
    mpv
    socat
    ripgrep
    procps
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
  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile ~/.ssh/github
      IdentitiesOnly yes
  '';
}
