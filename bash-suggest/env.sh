# Dev helper. Run inside `nix-shell` (see shell.nix) so rustc/cargo are on PATH.
# cb = cargo; kept so the commands in CLAUDE.md work unchanged.
command -v cargo >/dev/null || echo "env.sh: cargo not found, run nix-shell first" >&2
cb() { cargo "$@"; }
