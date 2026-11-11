# Brave Browser – oficjalna binarka z GitHub Releases (z autoPatchelfHook).
# GIT: brave – nixpkgs 26.05 usunął pakiet (brak maintainerów bezpieczeństwa); dodano: 2026-11-11
#
# Aktualizacja wersji:
#   1. Sprawdź nową wersję: https://github.com/brave/brave-browser/releases
#   2. Pobierz hash:
#        nix-prefetch-url "https://github.com/brave/brave-browser/releases/download/v<VER>/brave-browser_<VER>_amd64.deb"
#   3. Zaktualizuj pola `version` i `hash` poniżej.
{ pkgs, lib, ... }:

let
  brave = pkgs.stdenv.mkDerivation rec {
    pname = "brave";
    version = "1.99.56";  # https://github.com/brave/brave-browser/releases

    src = pkgs.fetchurl {
      url = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-browser_${version}_amd64.deb";
      # Uruchom: nix-prefetch-url "<url powyżej>" by uzyskać hash
      hash = "sha256-W1r00Qh1j+XoK3yxGa8gOXepD8s0ubBzGTF/hj84vHI=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.dpkg
      pkgs.wrapGAppsHook3
      pkgs.makeWrapper
    ];

    buildInputs = with pkgs; [
      # GTK / GLib
      gtk3
      glib
      at-spi2-atk
      cups
      dbus
      expat
      pango
      cairo
      # NSS / NSPR (TLS)
      nss
      nspr
      # GL / GPU
      libGL
      mesa
      libdrm
      # X11
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
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
      # Wayland
      libxkbcommon
      wayland
      # Dźwięk / urządzenia
      alsa-lib
      udev
    ];

    # Wyodrębnij .deb do bieżącego katalogu
    unpackPhase = "dpkg -x $src .";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/brave
      cp -a opt/brave.com/brave/. $out/lib/brave/

      # Wrapper: uruchamia brave z odpowiednimi zmiennymi Wayland
      mkdir -p $out/bin
      makeWrapper $out/lib/brave/brave-browser $out/bin/brave \
        --set NIXOS_OZONE_WL "1" \
        --add-flags "--enable-features=WaylandWindowDecorations" \
        --add-flags "--ozone-platform-hint=auto"

      # Plik .desktop i ikony
      mkdir -p $out/share
      cp -a usr/share/. $out/share/
      substituteInPlace $out/share/applications/brave-browser.desktop \
        --replace-fail "/opt/brave.com/brave/brave-browser" "$out/bin/brave"

      runHook postInstall
    '';

    meta = {
      description = "Privacy-focused web browser based on Chromium";
      homepage    = "https://brave.com";
      license     = lib.licenses.unfree;
      platforms   = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ brave ];
}
