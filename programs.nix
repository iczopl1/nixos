# Programy dla profilu full (dodatki ponad minimal).
# Ciężkie, kompilowane lub rzadko potrzebne narzędzia i IDE.
# mango.nix, keyboard-mouse.nix, crafts.nix i python.nix mają własne moduły.
{ pkgs, lib, config, unstable, ... }:

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

  # Grayjay Desktop – agregator wideo (YouTube, Twitch, Nebula…) by FUTO.
  # Nie ma w nixpkgs (nixpkgs buduje CEF ze źródeł – patrz BROKEN.md).
  # Tu: oficjalna binarka zip z updater.grayjay.app (bundlowany CEF, .NET self-contained).
  # GIT: grayjay-desktop – powód: brak w nixpkgs, nixpkgs kompiluje CEF – dodano: 2026-11-13
  grayjay = pkgs.stdenv.mkDerivation rec {
    pname = "grayjay-desktop";
    version = "20";

    src = pkgs.fetchurl {
      url = "https://updater.grayjay.app/Apps/Grayjay.Desktop/Grayjay.Desktop-linux-x64.zip";
      # sha256sum pobranego pliku | python3 -c "import base64,binascii,sys; h=sys.stdin.read().split()[0]; print('sha256-'+base64.b64encode(binascii.unhexlify(h)).decode())"
      hash = "sha256-011NbLZlrw3NUUXQPhkTEmgSzuikfEfCe8TAJeDkntg=";
    };

    nativeBuildInputs = with pkgs; [
      unzip
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = with pkgs; [
      # .NET self-contained (patchujemy ELF)
      stdenv.cc.cc.lib   # libstdc++, libgcc_s
      zlib
      openssl
      # CEF / Chromium bundlowane w cef/ – potrzebują system libs
      libx11
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxtst
      libxcb
      libxscrnsaver
      nss
      nspr
      atk
      at-spi2-atk
      at-spi2-core
      cups
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      pango
      alsa-lib
      libdrm
      mesa
      libxkbcommon
      wayland
      pipewire
    ];

    # Grayjay ładuje część libs przez dlopen – nie blokuj buildu na brakujących
    autoPatchelfIgnoreMissingDeps = true;

    dontBuild = true;
    dontConfigure = true;

    # ZIP rozpakowuje się do Grayjay.Desktop-linux-x64-v20/
    sourceRoot = "Grayjay.Desktop-linux-x64-v${version}";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt/grayjay
      cp -r . $out/opt/grayjay/
      chmod +x $out/opt/grayjay/Grayjay $out/opt/grayjay/Portable \
               $out/opt/grayjay/ffmpeg 2>/dev/null || true

      # Wrapper: LD_LIBRARY_PATH zawiera bundlowane cef/ i katalog główny
      mkdir -p $out/bin
      makeWrapper $out/opt/grayjay/Grayjay $out/bin/grayjay \
        --prefix LD_LIBRARY_PATH : "$out/opt/grayjay/cef:$out/opt/grayjay"

      # Ikona 256×256
      mkdir -p $out/share/icons/hicolor/256x256/apps
      cp grayjay.png $out/share/icons/hicolor/256x256/apps/app.grayjay.Grayjay.png \
        2>/dev/null || true

      # .desktop entry dla drun / rofi
      mkdir -p $out/share/applications
      cat > $out/share/applications/app.grayjay.Grayjay.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Grayjay
Comment=Universal media aggregator (YouTube, Twitch, Nebula…)
Categories=AudioVideo;Player;
Icon=app.grayjay.Grayjay
Exec=grayjay
Terminal=false
StartupWMClass=cef
DESKTOP

      runHook postInstall
    '';
  };

  # T3.13/T3.5: globalny licznik WPM – blokuje na select(), ~0% CPU, ~0.5 MB RAM.
  # Czyta /dev/input/event* (wymaga grupy `input`), ustawia focus_color w Mango.
  wpm-global = pkgs.callPackage ./wpm-global { };

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
    # T1.11b: Quickshell nowsza wersja z unstable (full zastępuje stable z minimal).
    # GIT: quickshell – nixpkgs 26.05 (0.3.0) brakuje layer_animations i nowych API; dodano: 2026-11-13
    # lib.hiPrio: wyższy priorytet niż stable quickshell z programs_minimal.nix
    (lib.hiPrio unstable.quickshell)

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
    wpm-global          # T3.13: globalny WPM → kolor obramówki w Mango
    google-chrome
    discord
    thunderbird     # T1.8: klient e-mail (wolny, z nixpkgs)
    beeper          # T1.9: komunikator all-in-one (Signal, WhatsApp, Telegram…) – unfree
    grayjay          # T1.10: agregator wideo FUTO; oficjalna binarka zip (CEF bundlowany, NIE kompilowany)
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

  # T1.12: Linksy camera – wirtualna kamera (v4l2loopback kernel module).
  # `linksy camera <device>` tworzy /dev/videoN z obrazem telefonu.
  # Użycie: linksy camera <nazwa-urządzenia>
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = ''
    options v4l2loopback video_nr=10 card_label="Linksy Camera" exclusive_caps=1
  '';

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
