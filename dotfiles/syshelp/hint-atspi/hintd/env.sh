# Dev toolchain from the Nix store (no rustc/gcc on PATH here). Builds use cores 1-11, never core 0.
export PATH=/nix/store/3sgpdha064vl7i8dr7g3d5wrc082d6g5-rustc-1.91.1/bin:/nix/store/kilyfvfmh9x9rlaj47ph1916lbc1pnsr-gcc-wrapper-14.3.0/bin:$PATH
cb() { taskset -c 1-11 cargo "$1" -j 11 "${@:2}"; }
