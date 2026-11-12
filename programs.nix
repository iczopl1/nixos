# Programy dla profilu full (dodatki ponad minimal).
# Ciężkie, kompilowane lub rzadko potrzebne narzędzia i IDE.
# mango.nix, keyboard-mouse.nix, crafts.nix i python.nix mają własne moduły.
{ pkgs, lib, ... }:

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
    # antigravity-cli – tylko w nixos-unstable (nie w nixpkgs 26.05); użyj nix-shell -p antigravity-cli

    # --- Biuro / grafika / dokumenty ---
    libreoffice            # libreoffice-fresh przemianowany (nixpkgs 26.05+)
    gimp
    krita
    texliveFull
    texlab
    pandoc
    graphviz

    # --- nvim LSP (Java) ---
    google-java-format
    java-language-server

    # --- Diagnostyka dysków (T2.2) ---
    gsmartcontrol         # GUI dla smartmontools (SMART, wykresy)

    # --- Narzędzia sieciowe – GUI (T2.3) ---
    wireshark             # GUI analizator pakietów (setuid przez programs.wireshark)

    # --- Chmura / transfery ---
    megatools             # T2.22: Mega.nz CLI (megaput, megaget, megals, megacopy…)

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
