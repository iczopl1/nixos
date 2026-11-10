# hintd: reads clickable AT-SPI fields and clicks through the wlr virtual pointer.
# Needs `mmsg` (Mango) on PATH at run time; the Mango session has it.
{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "hintd";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ];
  };
  cargoLock.lockFile = ./Cargo.lock;
}
