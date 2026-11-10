# clev: AI desktop navigation (accessibility tree first, SUPER+D hints as fallback).
# REVIEW COPY: this one file is all /etc/nixos needs. Import it from
# configuration.nix, rebuild, then log out/in (apps read the accessibility env at
# start). The rest is read from the repo below, so a rebuild picks up repo changes.
# Needs keyboard-mouse.nix (hint-click, wl-kbptr, ydotool) and clev.conf binds.
{ pkgs, ... }:
let
  src = ./hintdrive;

  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);

  # Byte-compiled once at build time: the CLI starts ~50 ms faster than when
  # Python has to compile the script on every call.
  clevLib = pkgs.runCommand "clev-lib" { } ''
    mkdir -p $out
    cp ${(src + "/clev.py")} $out/clev.py
    ${python}/bin/python3 -m compileall -q --invalidation-mode unchecked-hash $out
  '';

  clev = pkgs.writeShellApplication {
    name = "clev";
    runtimeInputs = [ python pkgs.grim pkgs.wtype pkgs.ydotool pkgs.libnotify pkgs.procps ];
    # hyprctl, hint-click, busctl, makoctl, claude, alacritty, wpctl, brightnessctl and
    # bluetoothctl come from the system PATH.
    runtimeEnv.GI_TYPELIB_PATH = "${pkgs.at-spi2-core}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0";
    runtimeEnv.CLEV_PLANNER_MD = "${(src + "/PLANNER.md")}";
    text = ''exec python3 -c 'import sys; sys.path.insert(0, "${clevLib}"); sys.argv[0] = "clev"; import clev; clev.main()' "$@"'';
  };

  clev-goal = pkgs.writeShellApplication {
    name = "clev-goal";
    runtimeInputs = [ clev pkgs.jq pkgs.wofi pkgs.libnotify pkgs.util-linux pkgs.pipewire ];
    # claude comes from the system PATH (dev.nix).
    text = builtins.replaceStrings [ "@driver_md@" "@sound@" ] [
      "${(src + "/DRIVER.md")}"
      "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/complete.oga"
    ]
      (builtins.readFile (src + "/clev-goal.sh"));
  };
in
{
  environment.systemPackages = [ clev clev-goal ];

  # Starts the accessibility bus and drops the NO_AT_BRIDGE=1 / GTK_A11Y=none
  # that NixOS exports while this is off, so GTK apps expose their widgets.
  # Firefox and Qt apps don't need anything more: they switch their trees on
  # live when clev sets org.a11y.Status.IsEnabled (tested with Firefox and
  # the KDE Connect daemon).
  services.gnome.at-spi2-core.enable = true;

  # Electron/Chromium apps (Discord, Signal, VSCodium) only build a tree when
  # started with --force-renderer-accessibility (ACCESSIBILITY_ENABLED=1 alone
  # didn't do it for Discord). `clev launch` adds the flag to the apps it
  # starts; one you started yourself without it is driven via SUPER+D hints.
}
