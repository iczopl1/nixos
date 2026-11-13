{ stdenv, lib }:
stdenv.mkDerivation {
  pname = "wpm-global";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./wpm-global.c;
  };
  dontConfigure = true;
  buildPhase = ''
    cc -O2 -o wpm-global wpm-global.c
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp wpm-global $out/bin/
  '';
}
