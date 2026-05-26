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
   slurp
   jq
   brightnessctl
   pavucontrol
   networkmanagerapplet
   #kdePackages.kdeconnect-kde
   iio-hyprland
   wvkbd
   yad
   ydotool
   mpc
   fzf
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
  google-chrome
  mesa-demos   # daje eglinfo
  android-studio
   android-tools
  jdk17
   wget
   cava
   discord
   python311
   python311Packages.pip
   python311Packages.virtualenv
   python311Packages.pinocchio
#programer tools
   gcc
   cmake
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
    noto-fonts
    noto-fonts-color-emoji
    fira-code
    jetbrains-mono
    nerd-fonts.symbols-only
    nerd-fonts.fira-code
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
    python3Packages.debugpy
# dodatkowe 
    anydesk
#Terminal program
    p7zip
    tree
    fastfetch
  ];
#opent tablet driver
  # Enable OpenTabletDriver
  hardware.opentabletdriver.enable = true;

  # Required by OpenTabletDriver
  hardware.uinput.enable = true;
  boot.kernelModules = [ "uinput" ];
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

   # potrzebne do uruchamiania binarek typu adb z SDK
  programs.nix-ld.enable = true;

  # opcjonalnie (ale pomaga)
  environment.variables = {
    JAVA_HOME = "${pkgs.jdk17}";
    CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome";
  };
 }
