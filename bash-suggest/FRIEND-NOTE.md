# bash-suggest: setup notes (NixOS)

Rust PTY wrapper that gives bash gray "ghost" suggestions and a fuzzy list
under the prompt. Read README.md for keys/limits, DESIGN.md for intent.

## Build

```bash
cd bash-suggest
nix-shell                      # gives rustc, cargo, gcc (shell.nix)
cargo build --release          # -> target/release/bash-suggest
cargo test                     # all tests (unit + e2e + init.bash)
```

Needs network on first build (crates.io: libc, memchr, rustix, vt100).

## Install

init.bash defaults to `~/syshelp/bash-suggest/target/release/bash-suggest`.
If you keep the folder elsewhere, set the binary path first.
Put these as the LAST lines of `~/.bashrc` (back it up first):

```bash
export BASH_SUGGEST_BIN=/path/to/bash-suggest/target/release/bash-suggest
source /path/to/bash-suggest/init.bash
```

Open a new terminal. Off for one shell: `BASH_SUGGEST=0 bash`.
If the binary is missing or crashes, init.bash falls back to plain bash.
Keep a terminal open while testing anyway.

On NixOS with `programs.bash` managed by home-manager, add the two lines via
`programs.bash.initExtra` (at the end) instead of editing ~/.bashrc.

## Debug

- Plain bash, no wrapper: `BASH_SUGGEST=0 bash`
- Force fallback path (test): `BASH_SUGGEST_FAIL=1 bash`
- Run one test group: `cargo test --test e2e`, `cargo test --bin bash-suggest keys`
- Speed check (50k history lines, must stay < 2 ms/key):
  `cargo test --release --bin bash-suggest bench_50k -- --ignored --nocapture`
- Per-shell temp files: `$XDG_RUNTIME_DIR/bash-suggest.<bash pid>.names` / `.env`

## Using with Claude (claude-agent / Claude Code)

- CLAUDE.md in this folder is the agent's project guide: layout, commands,
  safety rules. Claude loads it automatically when started in this folder.
- Its commands use `. ./env.sh && cb ...`; start claude from inside
  `nix-shell` so cargo is on PATH, and they work as written.
- CLAUDE.md mentions a `hidden-gui` skill: that is the original author's
  local skill, you won't have it. Prefer the e2e tests (they use a private pty).
- Paths `~/syshelp/...` in the docs are the original author's layout.
- Good first prompt: "read CLAUDE.md and DESIGN.md, build, run all tests,
  report failures".
