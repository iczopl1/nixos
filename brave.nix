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

    # Qt5/Qt6 shimy w Brave są opcjonalne (native file dialogs); bez Qt w buildInputs
    # autoPatchelfHook chciałby je linkować – ignorujemy, Brave odpada na GTK dialogi.
    autoPatchelfIgnoreMissingDeps = [ "libQt5*.so.5" "libQt6*.so.6" "libqt5*.so" "libqt6*.so" ];

    # Wyodrębnij .deb – bez próby ustawiania setuid (chrome-sandbox) w sandboxie Nix
    unpackPhase = ''
      dpkg-deb --fsys-tarfile $src | tar x --no-same-permissions --no-same-owner
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/brave
      cp -a opt/brave.com/brave/. $out/lib/brave/

      # Wrapper: uruchamia brave z odpowiednimi zmiennymi Wayland
      mkdir -p $out/bin
      makeWrapper $out/lib/brave/brave-browser $out/bin/brave \
        --set NIXOS_OZONE_WL "1" \
        --add-flags "--enable-features=WaylandWindowDecorations" \
        --add-flags "--ozone-platform-hint=auto" \
        --add-flags "--force-renderer-accessibility"

      # Plik .desktop i ikony
      mkdir -p $out/share
      cp -a usr/share/. $out/share/
      # Podmień ścieżkę Exec= – dopasuj dowolną ścieżkę (brave-browser lub brave-stable)
      sed -i "s|Exec=[^[:space:]]*|Exec=$out/bin/brave|g" \
        $out/share/applications/brave-browser.desktop

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

  # Brave managed policies – /etc/brave/policies/managed/policy.json
  # Dokumentacja: https://github.com/brave/brave-browser/wiki/Policies + Chromium policies
  environment.etc."brave/policies/managed/policy.json".text = builtins.toJSON {
    # --- AI (Leo) wyłączony ---
    BraveAIChatEnabled = false;

    # --- Telemetria i raporty wyłączone ---
    MetricsReportingEnabled          = false;
    CloudReportingEnabled            = false;

    # --- Hasła: używamy KeePassXC, nie Brave ---
    PasswordManagerEnabled  = false;
    AutofillAddressEnabled  = false;
    AutofillCreditCardEnabled = false;

    # --- Wyszukiwarka domyślna: DuckDuckGo zamiast Google ---
    DefaultSearchProviderEnabled   = true;
    DefaultSearchProviderName      = "DuckDuckGo";
    DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
    DefaultSearchProviderSuggestURL = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";

    # --- Brave Rewards wyłączone ---
    BraveRewardsEnabled = false;

    # --- spell: sprawdzanie pisowni (pl + en) ---
    SpellCheckServiceEnabled = true;
    SpellcheckLanguage      = [ "pl" "en-US" ];

    # --- T3.8: Rozszerzenia wymuszone (KeePassXC) ---
    # ID: pdffhmdngcdnblkagkiocabomlahoihh = KeePassXC-Browser (Chrome Web Store)
    ExtensionInstallForcelist = [
      "pdffhmdngcdnblkagkiocabomlahoihh;https://clients2.google.com/service/update2/crx"
    ];

    # --- T2.10: Zakładki zarządzane ---
    ManagedBookmarks = [
      { name = "AI"; children = [
          { name = "Claude";      url = "https://claude.ai"; }
          { name = "ChatGPT";     url = "https://chat.openai.com"; }
          { name = "Gemini";      url = "https://gemini.google.com"; }
          { name = "Le Chat";     url = "https://chat.mistral.ai"; }
          { name = "Perplexity";  url = "https://www.perplexity.ai"; }
        ];
      }
      { name = "Google"; children = [
          { name = "Drive"; url = "https://drive.google.com"; }
          { name = "Gmail"; url = "https://mail.google.com"; }
          { name = "Mega.nz"; url = "https://mega.nz"; }
        ];
      }
      { name = "Local"; children = [
          { name = "Syncthing"; url = "http://localhost:8384"; }
        ];
      }
    ];
  };
}
