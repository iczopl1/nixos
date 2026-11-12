# Programy dla profilu full (dodatki ponad minimal).
# Ciężkie, kompilowane lub rzadko potrzebne narzędzia i IDE.
# mango.nix, keyboard-mouse.nix, crafts.nix i python.nix mają własne moduły.
{ pkgs, lib, ... }:

let
  # Linksy – integracja PC↔telefon (pliki, schowek, ekran, kamera, BT).
  # Nie ma w nixpkgs; binarka z oficjalnych GitHub Releases (MASTER §13 kolejność 2).
  # GIT: linksy – powód: brak w nixpkgs – dodano: 2026-11-12
  # Wymagania: GTK 4.14+, libadwaita 1.6+; screen/kamera: GStreamer + PipeWire (services.nix).
  # Firewall: UDP 47200 otwarte w security.nix.
  linksy = pkgs.stdenv.mkDerivation rec {
    pname = "linksy";
    version = "0.8.0";

    src = pkgs.fetchurl {
      url = "https://github.com/LinkSy-mg/linksy-releases/releases/download/linux-v${version}/linksy-${version}-linux-x86_64.tar.gz";
      hash = "sha256-MT6SoPMo8nW8nLv3jqJCM9PEklH5Rufen+H0J1STKBM=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.wrapGAppsHook4   # obsługuje GTK4 schemas, ikony, GLib i/o modules
    ];

    buildInputs = with pkgs; [
      gtk4
      libadwaita
      glib
      pango
      cairo
      graphene
      harfbuzz
      gdk-pixbuf
      # GStreamer (screen-share, kamera)
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      # Sieć i TLS
      libsoup_3
      glib-networking
      openssl
      # Audio/wideo
      pipewire
      libpulseaudio
    ];

    # Nie przerywaj buildu na brakujących bibliotekach – mogą być ładowane przez dlopen
    autoPatchelfIgnoreMissingDeps = true;

    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      runHook preInstall
      echo "=== Zawartość tarballa ==="
      find . -ls
      mkdir -p $out/bin $out/share/applications $out/share/icons

      # Kopiuj wszystkie pliki wykonywalne z bin/ (lub z katalogu głównego)
      if [ -d bin ]; then
        cp -r bin/. $out/bin/
      else
        find . -maxdepth 1 -type f -executable -exec cp {} $out/bin/ \;
      fi

      # Desktop entry i ikony (toleruje brak pliku)
      find . -name "*.desktop" -exec cp {} $out/share/applications/ \; 2>/dev/null || true
      if [ -d share/icons ]; then
        cp -r share/icons/. $out/share/icons/
      fi

      runHook postInstall
    '';
  };

  # T2.23: JDownloader 2 – nie ma w nixpkgs; własna derywacja z oficjalnego Setup jara.
  # GIT: nie dotyczy – pobieramy oficjalny jar z serwera JDownloader
  # Przy pierwszym uruchomieniu (brak ~/JDownloader2/JDownloader2.jar) odpala Setup jar
  # z GUI instalatorem → instaluje do ~/JDownloader2/.  Kolejne uruchomienia startują bezpośrednio.
  # JDownloader sam się aktualizuje, więc wersja jara w Nix nie ma znaczenia.
  jd2SetupJar = pkgs.fetchurl {
    url = "https://jdownloader.org/downloads/jdownloader2/appwork/JDownloader2Setup.jar";
    sha256 = "0h0jbc05rhz4hhz128q23rwg0sjj2745fq2fkmkv4iglwpyi8d2x";
  };

  jdownloader2 = pkgs.writeShellScriptBin "jdownloader" ''
    JD2_HOME="$HOME/JDownloader2"
    JD2_JAR="$JD2_HOME/JDownloader2.jar"
    JAVA="${pkgs.jdk17}/bin/java"

    if [ ! -f "$JD2_JAR" ]; then
      echo "JDownloader 2: pierwsze uruchomienie – instalacja do $JD2_HOME"
      echo "(otworzy się okno instalatora, wybierz $JD2_HOME jako katalog)"
      mkdir -p "$JD2_HOME"
      "$JAVA" -jar "${jd2SetupJar}" -noexit -q -dir "$JD2_HOME" 2>/dev/null \
        || "$JAVA" -jar "${jd2SetupJar}"
    fi

    if [ -f "$JD2_JAR" ]; then
      exec "$JAVA" -jar "$JD2_JAR" "$@"
    else
      echo "Instalacja nie powiodła się. Uruchom ręcznie:"
      echo "  java -jar ${jd2SetupJar}"
      exit 1
    fi
  '';
in

{
  environment.systemPackages = with pkgs; [
    # --- Pulpit (extra, full) ---
    kitty
    waybar
    wofi
    dunst
    glava
    eww
    pywal
    cava
    mpc

    # --- Komunikacja ---
    # brave – w brave.nix (oficjalna binarka z GitHub Releases, nixpkgs 26.05 usunął pakiet)
    linksy
    google-chrome
    discord
    # anydesk – usunięty: brak kompatybilnych bibliotek GUI dla Mango

    # --- IDE / edytory ---
    vscodium
    # android-studio – usunięty: broken download (patrz BROKEN.md)
    android-tools
    flutter
    mesa-demos            # eglinfo

    # --- Programowanie (full) ---
    (lib.lowPrio clang)   # lowPrio: `cc` zostaje z gcc (z minimal)
    clang-tools
    ninja
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

    # --- AI (full) ---
    # claude-code i antigravity-cli (agy) są w programs_minimal.nix

    # --- Biuro / grafika / dokumenty ---
    libreoffice            # libreoffice-fresh przemianowany (nixpkgs 26.05+)
    gimp
    krita
    texliveFull
    texlab
    pandoc
    graphviz

    # --- nvim LSP (T3.4: full) ---
    google-java-format
    java-language-server
    typescript-language-server   # JS/TS LSP
    vscode-langservers-extracted # HTML/CSS/JSON/ESLint LSP (vscode-html-languageserver itp.)
    rust-analyzer                # Rust LSP
    gopls                        # Go LSP
    kotlin-language-server       # Kotlin LSP

    # --- Diagnostyka dysków (T2.2) ---
    gsmartcontrol         # GUI dla smartmontools (SMART, wykresy)

    # --- Narzędzia sieciowe – GUI (T2.3) ---
    wireshark             # GUI analizator pakietów (setuid przez programs.wireshark)

    # --- Chmura / transfery ---
    megatools             # T2.22: Mega.nz CLI (megaput, megaget, megals, megacopy…)
    jdownloader2          # T2.23: JDownloader 2 – wrapper; Setup jar pobiera app do ~/JDownloader2/

    # --- Bezpieczeństwo ---
    maltego

    # --- Gry ---
    prismlauncher

    # --- Embedded / mikrokontrolery (T3.10) ---
    arduino-ide           # IDE 2.x – Nice Nano (nRF52840) przez UF2/DFU
    gcc-arm-embedded      # arm-none-eabi toolchain (STM32, nRF52, Cortex-M)
    openocd               # On-Chip Debugger – flash/debug STM32 przez ST-Link
    stlink                # ST-Link narzędzia CLI (st-flash, st-info, st-util)
    dfu-util              # DFU – bootloader Nice Nano (nRF52840)
    stm32flash            # flash STM32 przez UART (alternatywa dla ST-Link)
    platformio            # PlatformIO CLI – ESP32, AVR, STM32, nRF (framework+upload)
    esptool               # esptool.py – flash ESP32/ESP8266 przez UART
  ];

  # Steam – moduł NixOS: obsługuje 32-bit libs, udev, gamescope opcjonalnie
  programs.steam.enable = true;

  # Wireshark – setuid wrapper dla dumpcap (przechwytywanie bez root) + udev (T2.3)
  programs.wireshark.enable = true;
  users.users.iczo.extraGroups = [ "wireshark" ];

  # OpenTabletDriver (graficzny tablet)
  hardware.opentabletdriver.enable = true;

  # Wirtualizacja (libvirt/QEMU)
  virtualisation.libvirtd.enable = true;

  # udev rules dla embedded – Arduino IDE i ST-Link (dostęp bez sudo)
  services.udev.packages = with pkgs; [
    arduino-ide  # /dev/ttyUSB*, /dev/ttyACM* dla programatorów Arduino
    stlink       # ST-Link V2/V3 (STM32)
  ];

  environment.variables = {
    JAVA_HOME = "${pkgs.jdk17}";
    CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome";
  };
}
