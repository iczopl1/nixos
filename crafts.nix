# storytold "Craft" apps (ArtCraft suite), built from source.
#
# NixOS module: import it from configuration.nix (`./crafts.nix`). Self-contained:
# it pins its own nixpkgs (the apps need rustc >= 1.95, newer than 25.11), so channel
# updates never trigger a rebuild of these apps.
#
# Each app installs `<app>` (desktop GUI, with .desktop entry + icons) and `<app>-cli`.
#
# Built with crane: every app's crates.io/git dependencies are compiled in a separate,
# cached derivation. Bumping an app to a newer commit only recompiles that app's own
# code, unless the commit changes its Cargo.lock/Cargo.toml dependencies.
#
# To update an app to a newer commit:
#   1. set its `rev` below
#   2. set its `hash` to lib.fakeHash (or "")
#   3. rebuild; paste the "got: sha256-..." from the error into `hash`
# To leave an app out, comment out its entry.
#
# Toolchains: apps build with nixpkgs' own rustc from `nixpkgsPin` (nixos-unstable) unless
# their entry says `toolchain = "official";`, which uses the upstream Rust release binaries
# (via rust-overlay, version `officialRust`) on the same nixpkgs. Moving a pin rebuilds every
# app that uses it.
{ lib, ... }:

let
  nixpkgsPin = {
    # nixos-unstable, 2026-10-06 (rustc 1.98.1)
    url = "https://github.com/NixOS/nixpkgs/archive/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4.tar.gz";
    sha256 = "0rm5v6n0kgqq5xrc34imn8nxx0y2xlmhpa0nag9sk6m6ys9slaij";
  };
  rustOverlayPin = {
    # oxalica/rust-overlay, 2026-10-08
    url = "https://github.com/oxalica/rust-overlay/archive/f91010a5c1b6125b715eb78a84fb5dd8fb74a2b0.tar.gz";
    sha256 = "1fsr5dvxqfd6vb0rb9lkzrgq3s4ddbxzq3z1c65pkv73bl8177hw";
  };
  officialRust = "1.98.1";
  cranePin = {
    # ipetkov/crane, 2026-10-02
    url = "https://github.com/ipetkov/crane/archive/47b6b27ed9a3a9181415e4367d0c30ab2a0e0250.tar.gz";
    sha256 = "10sphf5jyw5s2x65lwj3xy9qq853bga8knc9n8z9a62lmv7sswac";
  };

  crane = import (builtins.fetchTarball cranePin);
  toolchains = {
    unstable = rec {
      pkgs = import (builtins.fetchTarball nixpkgsPin) { };
      craneLib = crane { inherit pkgs; };
    };
    official = rec {
      pkgs = import (builtins.fetchTarball nixpkgsPin) {
        overlays = [ (import (builtins.fetchTarball rustOverlayPin)) ];
      };
      craneLib = (crane { inherit pkgs; }).overrideToolchain (
        p: p.rust-bin.stable.${officialRust}.minimal
      );
    };
  };

  apps = {
    # The seven ArtCraft "Adobe alternatives"
    photocraft = {
      rev = "5896f0b63e6f342e0311920b4d2a0ea5a94330fc";
      hash = "sha256-HzQ9NnOo9ZL4zd/ArhdMSdW441C+/6AAZLpe72lh6aA=";
      description = "Image editor (Photoshop-style)";
    };
    vectorcraft = {
      rev = "d66a8b61278e62ac15bf412a5399b24cbe2a328f";
      hash = "sha256-Hk8a5OGwpeCMSa3bfHv2OCXjGZsc4NKMaCy86UkSzUg=";
      description = "Vector illustration (Illustrator-style)";
    };
    filmcraft = {
      rev = "61238bf8fc129077fe2b7982550303be49f55a93";
      hash = "sha256-KI8c9tytYkR1ErOf4WpRBFNj8Ef/NVhAAVvryOSTNaA=";
      description = "Video editor (Premiere Pro-style)";
      audio = true;
      gtk = true;
    };
    lightcraft = {
      rev = "629e39380e296f588c64cd9c0053a8edc3528f36";
      hash = "sha256-nHMPgvShko4hlkm962jPYhCBV3FZnCkYCNWBVW+J/Ls=";
      description = "Photo library and raw developer (Lightroom-style)";
    };
    pdfcraft = {
      rev = "1d31c230c993f15aa6d206fb167236a15c259dfb";
      hash = "sha256-mQUTwzrNnt55q/sa6OuG/mbctavmdqSjnYnj8g2jynQ=";
      description = "PDF editor (Acrobat-style)";
      # rten-gemm's AVX-512 intrinsics need the LLVM 22 that upstream rustc 1.98 ships;
      # nixpkgs builds rustc 1.98 against LLVM 21, where they don't compile.
      toolchain = "official";
    };
    effectcraft = {
      rev = "c486130a9b72e47fe020da0f6115d0261716df5f";
      hash = "sha256-hfFT/nMvXn7KD4wHmOipsFe7K2waUbxnA92W5tlp++M=";
      description = "Motion graphics (After Effects-style)";
      audio = true;
    };
    designcraft = {
      rev = "f4a4c9709b7c552800f15ba3d1f0f68dd75fa165";
      hash = "sha256-rIxYWYE2DwJhV3OUvo9vbABMZZcEPXKY2Padabr16s0=";
      description = "Page layout (InDesign-style)";
    };

    # Other Craft apps
    gridcraft = {
      rev = "c6b6f4177cbf52aa7a8bac8aa15650a7502926fe";
      hash = "sha256-Vh+YxTDDJfg4GK4lpN/1Kkm7HDnMdDz1J9UoQExZAuI=";
      description = "Spreadsheet (Excel-style)";
    };
    cadcraft = {
      rev = "1d7ea8749f602ad09764504ddfee2469929428b1";
      hash = "sha256-NswyOijCMaKx1hP35Iw5ae7B6wBapJR8XvO//rzXdSE=";
      description = "CAD and drafting (AutoCAD-style)";
    };
    deckcraft = {
      rev = "286ff74c8ba9be7e8ec110783b3d22beb8052341";
      hash = "sha256-V7Le/H3QL1cYjWkJHuAUky2vGzy1tGHSV/cnRBYUW7I=";
      description = "Presentations (PowerPoint-style)";
      audio = true;
    };
    soundcraft = {
      rev = "9334ba0a507f52321f1f0f7f7ae0883d2da07679";
      hash = "sha256-Ta1effawrWUThVUeXehyrBIsR/o345ACs5nT8kEWyas=";
      description = "Audio workstation (Pro Tools-style)";
      audio = true;
    };
    wordcraft = {
      rev = "db0cfed1f78f4e82b77b922b6006f56a842c8e50";
      hash = "sha256-GwOKFOH2EUWuxFtYOsG2aWRa0pnkMVw4l1wXXGk2kcg=";
      description = "Word processor (Word-style)";
    };
  };

  # CJK fonts embedded at build time (same pin the apps' release workflow uses).
  # Without them the apps work, but Japanese/Chinese text has no glyphs.
  craftFonts = toolchains.unstable.pkgs.fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "abb83316d96aa59c1cf64784289e378fe9fa5695";
    hash = "sha256-e+6HpOYoAFTh6mNfGBBw2njnBzcE8W8+Jybv1+dKOCA=";
  };

  mkCraft =
    name: app:
    let
      inherit (toolchains.${app.toolchain or "unstable"}) pkgs craneLib;
      appId = "ai.storyteller.${name}";
      # dlopen()ed at run time by winit (Wayland/X11 + xkbcommon) and wgpu (Vulkan).
      runtimeLibs = with pkgs; [
        libxkbcommon
        wayland
        libx11
        libxcb
        libxcursor
        libxi
        libxrandr
        vulkan-loader
      ];
      audio = app.audio or false;
      gtk = app.gtk or false;

      src = pkgs.fetchFromGitHub {
        owner = "storytold";
        repo = name;
        inherit (app) rev hash;
      };

      cargoToml = builtins.fromTOML (builtins.readFile "${src}/Cargo.toml");
      version = cargoToml.workspace.package.version or "0-unstable";

      commonArgs = {
        pname = name;
        inherit version src;
        strictDeps = true;
        cargoExtraArgs = "--locked -p ${name} -p ${name}-cli";

        # Full workspace test suites; skipped to keep rebuilds fast.
        doCheck = false;

        nativeBuildInputs =
          with pkgs;
          [
            pkg-config
            wayland-scanner
          ]
          ++ lib.optional gtk wrapGAppsHook3;

        buildInputs =
          with pkgs;
          [
            wayland
            libxkbcommon
            libx11
            libxcb
            libxcursor
            libxi
            libxrandr
          ]
          ++ lib.optional audio alsa-lib
          ++ lib.optional gtk gtk3;

        env = {
          CRAFT_FONTS_DIR = toString craftFonts;
          RUSTFLAGS = "-Awarnings";
        };
      };

      # Dependencies only; reused as long as the app's Cargo.lock/Cargo.toml deps are unchanged.
      cargoArtifacts = craneLib.buildDepsOnly (
        commonArgs
        // {
          cargoCheckCommand = "true"; # skip the extra `cargo check` pass
        }
      );
    in
    craneLib.buildPackage (
      commonArgs
      // {
        inherit cargoArtifacts;

        nativeBuildInputs =
          commonArgs.nativeBuildInputs
          ++ (with pkgs; [
            makeWrapper
            autoAddDriverRunpath
          ]);

        dontWrapGApps = true; # folded into the single wrapProgram below

        postInstall = ''
          linux=packaging/linux
          if [ -f $linux/${appId}.desktop ]; then
            install -Dm644 $linux/${appId}.desktop $out/share/applications/${appId}.desktop
          fi
          if [ -f $linux/${appId}.mime.xml ]; then
            install -Dm644 $linux/${appId}.mime.xml $out/share/mime/packages/${appId}.xml
          fi
          if [ -f $linux/${appId}.metainfo.xml.in ]; then
            install -d $out/share/metainfo
            substitute $linux/${appId}.metainfo.xml.in $out/share/metainfo/${appId}.metainfo.xml \
              --subst-var-by VERSION ${version} --subst-var-by DATE 1970-01-01
          fi

          if [ -d assets/app-icon/hicolor ]; then
            mkdir -p $out/share/icons
            cp -r assets/app-icon/hicolor $out/share/icons/
          else
            for s in 64 256 1024; do
              f=assets/app-icon/${name}-$s.png
              [ -f $f ] && install -Dm644 $f $out/share/icons/hicolor/''${s}x''${s}/apps/${appId}.png
            done
          fi
        '';

        postFixup = ''
          for bin in $out/bin/${name} $out/bin/${name}-cli; do
            [ -e "$bin" ] || continue
            wrapProgram "$bin" \
              --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
              ${lib.optionalString gtk ''"''${gappsWrapperArgs[@]}"''}
          done
        '';

        meta = {
          inherit (app) description;
          homepage = "https://github.com/storytold/${name}";
          license = with lib.licenses; [
            mit
            asl20
          ];
          platforms = lib.platforms.linux;
          mainProgram = name;
        };
      }
    );

  crafts = lib.mapAttrs mkCraft apps;
in
{
  environment.systemPackages = lib.attrValues crafts;
}
