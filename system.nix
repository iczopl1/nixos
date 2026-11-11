# Ustawienia systemowe: boot, sieć, locale, użytkownik, bluetooth, libvirt.
{ config, pkgs, ... }:

{
  # Kernel zen – responsywność desktopu (MASTER §3). Pochodzi z cache nixpkgs, bez kompilacji.
  boot.kernelPackages = pkgs.linuxPackages_zen;

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
    # "ydotool": wymagane przez keyboard-mouse.nix / hintd (tryb kursora)
    extraGroups = [ "networkmanager" "wheel" "adbusers" "libvirtd" "kvm" "ydotool" ];
    packages = [ ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Czujnik orientacji ekranu (zastępuje iio-hyprland). mango.nix włącza
  # iio-sensor-proxy przy starcie; ta opcja zapewnia, że usługa w ogóle istnieje.
  hardware.sensor.iio.enable = true;

  # flutter setup
  environment.sessionVariables = {
    XDG_DATA_DIRS = [ "/run/current-system/sw/share" ];
  };

  # android-studio / emulatory
  programs.adb.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.dconf.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
