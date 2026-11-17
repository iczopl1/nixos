# Ustawienia systemowe: boot, sieć, locale, użytkownik, bluetooth, libvirt.
{ config, pkgs, ... }:

{
  # Kernel zen – responsywność desktopu (MASTER §3). Pochodzi z cache nixpkgs, bez kompilacji.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # T1.13: zram – swap kompresowany w RAM (MASTER §3 "opcjonalnie, z cache, bez kompilacji").
  # Na 8 GB RAM: 50% → 4 GB zram. Mniej przycinania gdy build full zajmuje dużo pamięci.
  zramSwap = {
    enable    = true;
    algorithm = "zstd";   # najlepszy stosunek kompresji do CPU na Broadwell
  };

  boot.loader = {
    timeout = 10;
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = false;
      useOSProber = true;
    };
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
  };

  networking.hostName = "ThinkPadNIX";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Warsaw";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pl_PL.UTF-8";
    LC_IDENTIFICATION = "pl_PL.UTF-8";
    LC_MEASUREMENT = "pl_PL.UTF-8";
    LC_MONETARY = "pl_PL.UTF-8";
    LC_NAME = "pl_PL.UTF-8";
    LC_NUMERIC = "pl_PL.UTF-8";
    LC_PAPER = "pl_PL.UTF-8";
    LC_TELEPHONE = "pl_PL.UTF-8";
    LC_TIME = "pl_PL.UTF-8";
  };

  console.keyMap = "pl2";

  users.users.iczo = {
    isNormalUser = true;
    description = "iczo";
    # "ydotool": keyboard-mouse.nix (full); "adbusers"/"libvirtd": programs.nix (full)
    # Grupy tworzone przez moduły full – definiujemy je jawnie, by istniały też w minimal.
    extraGroups = [ "networkmanager" "wheel" "adbusers" "libvirtd" "kvm" "ydotool" "dialout" "plugdev" "input" ];
    packages = [ ];
  };

  # Grupy wymagane przez moduły full; definiowane tutaj by istniały też w profilu minimal.
  users.groups.ydotool  = {};   # programs.ydotool.enable (keyboard-mouse.nix)
  users.groups.adbusers = {};   # programs.adb.enable (programs.nix)
  users.groups.libvirtd = {};   # virtualisation.libvirtd.enable (programs.nix)

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Czujnik orientacji ekranu (zastępuje iio-hyprland). mango.nix włącza
  # iio-sensor-proxy przy starcie; ta opcja zapewnia, że usługa w ogóle istnieje.
  hardware.sensor.iio.enable = true;

  # Sprzętowe dekodowanie/kodowanie wideo (VAAPI) – iGPU Intel HD 5500 (Broadwell, X250).
  # Bez tego Discord/Brave/mpv/Moonlight itp. cicho spadają na dekodowanie programowe
  # (stąd np. nieszkodliwie wyglądający warning "vaInitialize failed" u Discorda – to
  # NIE było niegroźne, tylko brak sterownika w ogóle).
  # Zweryfikowane realnym `vainfo` na tym GPU (2026-11-17):
  #   - intel-media-driver (iHD) – DZIAŁA, pełne VAProfileH264Main/VAEntrypointVLD.
  #   - intel-vaapi-driver (i965, starszy) – `init failed`, vaInitialize -1. Nie dodany,
  #     żeby auto-detekcja nigdy nie trafiła na zepsuty sterownik.
  # LIBVA_DRIVER_NAME przypięty na pewniaka (zamiast auto-detekcji) z tego samego powodu.
  # Wymagane dla najmniejszego opóźnienia w Moonlight (shell.nix: rd/rdm).
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver libvdpau-va-gl ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # flutter setup
  environment.sessionVariables = {
    XDG_DATA_DIRS = [ "/run/current-system/sw/share" ];
  };

  # android-studio / emulatory (programs.adb usunięte w 26.05 – systemd 258 przejął uaccess)
  virtualisation.libvirtd.enable = true;
  programs.dconf.enable = true;

  # T3.6: AltGr+Ctrl jako drugi Super (xkb remap przez keyd – działa na poziomie kernela, Wayland-OK).
  # RightAlt (AltGr) przytrzymane aktywuje warstwę altgr; w tej warstwie Ctrl = leftmeta (Super).
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "k:*" ];  # tylko klawiatury – "*" przechwytywało też mysz i blokało klikanie
        settings = {
          main = {
            rightalt = "layer(altgr)";
          };
          "altgr" = {
            leftcontrol  = "leftmeta";
            rightcontrol = "leftmeta";
          };
        };
      };
    };
  };

  # nixos-rebuild-ng (Python, NixOS 26.05+) czyta nixos-config z /etc/nix/nix.conf (nix-path),
  # a nie z NIX_PATH env. Wskazujemy na symlink tworzony przez rebuild.sh, który zawsze
  # wskazuje na właściwy plik wejściowy (configuration.nix lub configuration_minimal.nix),
  # niezależnie od profilu i lokalizacji repo.
  nix.nixPath = [
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "nixos-config=/etc/nixos/active-configuration.nix"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  # T2.31: nix-direnv – używa flake-less nix-shell (keep-env-derivations)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Cache – pobieraj z cache zamiast kompilować (MASTER §4/§13)
    substituters = [ "https://cache.nixos.org/" ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # Równoległe pobieranie z cache (domyślnie 16, zostawiamy)
    max-substitution-jobs = 16;

    # Hard-linkuj identyczne pliki w /nix/store – mniej miejsca, szybszy GC
    auto-optimise-store = true;

    # Trzymaj outputy buildów – nie będą kasowane przy GC, nie trzeba pobierać ponownie
    keep-outputs = true;
    keep-derivations = true;
  };

  # Budowanie w tle nie blokuje pracy (MASTER §5)
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # T2.30: cotygodniowy GC – usuwa generacje starsze niż 14 dni, zostawia >= 5
  # Bez tego każdy rebuild zostawia generację na dysku na zawsze.
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 14d";
  };
  nix.settings.min-free = 1024 * 1024 * 512;   # 512 MB – trigger GC gdy dysk się kończy

  # Wyłącz budowanie dokumentacji NixOS (options.json, man-pages) – nie potrzebne na desktopie,
  # a moduły custom mogą powodować błędy eval-cacheable-options w sandboxie.
  documentation.nixos.enable = false;

  system.stateVersion = "25.11";
}
