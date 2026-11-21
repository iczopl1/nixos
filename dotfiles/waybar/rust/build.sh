#!/bin/sh
# Build the waybar widgets binary: rust/target/release/wbw
cd "$(dirname "$0")" && exec nix-shell -p cargo gcc --run "cargo build --release"
