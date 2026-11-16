# Webots – symulator robotów mobilnych (Cyberbotics), do ćwiczeń Khepera III.
# Nie ma w nixpkgs (sprawdzone: brak pakietu "webots" w nixpkgs). Open source (Apache-2.0),
# więc nie trzeba unfree. Oficjalna binarka z GitHub Releases (MASTER §13 kolejność 2).
# GIT: webots – powód: brak w nixpkgs – dodano: 2026-11-16
#
# Zależności (nieopakowane w samym tarballu) ustalone przez realny `readelf -d` na
# webots-bin + biblioteki z lib/webots/ (Qt6 bundlowany, OpenAL/ODE/assimp/OIS/pico też
# bundlowane – autoPatchelfHook znajduje je sam w $out, nie trzeba ich w buildInputs).
#
# WEBOTS_HOME: sterownik Pythona (`from controller import Robot`) czyta tę zmienną
# i ładuje $WEBOTS_HOME/lib/controller/libController.so przez ctypes (czyste .py,
# bez kompilowanego rozszerzenia per-wersja Pythona – działa z dowolnym python3).
# Webots ustawia ją sam dla kontrolerów uruchamianych przyciskiem "Run" w IDE;
# dla uruchomień poza IDE (np. testy w terminalu) jest też ustawiona systemowo niżej.
#
# Aktualizacja wersji:
#   1. Sprawdź nową wersję: https://github.com/cyberbotics/webots/releases
#   2. Pobierz hash:
#        nix-prefetch-url "https://github.com/cyberbotics/webots/releases/download/<TAG>/webots-<TAG>-x86-64.tar.bz2"
#   3. Zaktualizuj pola `version` i `hash` poniżej.
{ pkgs, lib, ... }:

let
  webots = pkgs.stdenv.mkDerivation rec {
    pname = "webots";
    version = "R2025a";  # https://github.com/cyberbotics/webots/releases

    src = pkgs.fetchurl {
      url = "https://github.com/cyberbotics/webots/releases/download/${version}/webots-${version}-x86-64.tar.bz2";
      hash = "sha256-xRJ/tCBsV6WuVSPxt/Pai2cLyJJtmuCFleE58ibzjDg=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
    ];

    buildInputs = with pkgs; [
      # GL / GLU / EGL – rendering 3D sceny
      libGL
      libGLU
      libglvnd
      mesa
      # X11 / xcb – Qt6 platform plugin "xcb" (webots wymusza QT_QPA_PLATFORM=xcb)
      libx11
      libxcb
      libxkbcommon
      # Qt core zależności nie-bundlowane
      fontconfig
      glib
      zlib
      krb5          # libgssapi_krb5 – QtNetwork
      sndio         # libopenal (bundlowany) linkuje libsndio
      libxml2       # libxslt (bundlowany, eksport/import scen) linkuje libxml2
      # libstdc++ dla webots-bin i bibliotek bundlowanych (ODE, assimp, OIS…)
      stdenv.cc.cc.lib
      # Eksport filmów z symulacji (opcjonalny, dlopen)
      ffmpeg
    ];

    # Webots dlopen'uje część kodeków/pluginów – nie przerywaj buildu na brakujących
    autoPatchelfIgnoreMissingDeps = true;

    dontBuild = true;
    dontConfigure = true;
    dontStrip = true;   # pliki Qt bundlowane przez Cyberbotics – nie ruszamy ich strip/patchelf poza RPATH

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt
      cp -r . $out/opt/webots

      mkdir -p $out/bin
      makeWrapper $out/opt/webots/webots $out/bin/webots \
        --set WEBOTS_HOME "$out/opt/webots"

      # .desktop entry i ikona dla drun/rofi
      mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
      cp $out/opt/webots/resources/icons/core/webots.png \
        $out/share/icons/hicolor/256x256/apps/webots.png
      cat > $out/share/applications/webots.desktop << DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Webots
Comment=Mobile robot simulator (Cyberbotics)
Categories=Science;Engineering;
Icon=webots
Exec=$out/bin/webots
Terminal=false
DESKTOP

      runHook postInstall
    '';

    meta = {
      description = "Open-source mobile robot simulator";
      homepage    = "https://cyberbotics.com";
      license     = lib.licenses.asl20;
      platforms   = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ webots ];

  # Pozwala uruchamiać skrypty Pythona korzystające z `from controller import Robot`
  # poza IDE Webots (np. `python3 FuzzyAvoid.py` w terminalu) bez ręcznego exportu.
  environment.variables = {
    WEBOTS_HOME = "${webots}/opt/webots";
  };
}
