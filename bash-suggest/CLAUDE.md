# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

bash-suggest: Rust PTY wrapper that gives bash gray ghost suggestions and a fuzzy
list under the prompt. Top priority: very low CPU and fast.

No subsystem CLAUDE.md files.

## Layout

```
src/main.rs      poll loop: moves bytes between terminal, pty and App; signals
src/app.rs       all decisions: markers, cursor query, settle timer, draw/erase, accept
src/pty.rs       spawn `bash -i` on a new pty (BASH_SUGGEST=1)
src/term.rs      raw mode + restore, window size, signal self-pipe
src/markers.rs   finds OSC 133 A/B/C and ESC[?2004h/l in bash output (no copy)
src/screen.rs    vt100 mirror of the screen, ONLY while at a prompt; reads typed line
src/keys.rs      key state machine (Right, Tab, Shift-Tab, Up/Down, Enter, Esc); edit_bytes
src/render.rs    escape bytes for ghost text, list, erase (pure)
src/suggest.rs   ranking from all sources
src/sources.rs   history (incremental), PATH, names file, dirs, subcommands
src/fuzzy.rs     fzf-v1 style scorer
init.bash        sourced from ~/.bashrc: outer shell execs the wrapper, inner shell adds hooks
tests/           relay.rs, e2e.rs (private pty + vt100 terminal answering ESC[6n), init_bash.rs
```

How it fits: bash output -> `markers` -> at `133;B` App sends `ESC[6n`, starts the
`screen` mirror at the reply position -> 5 ms quiet -> `suggest` -> `render`.
Any new bash output or key first erases what was drawn.

## Commands

No rustc on PATH: always `. ./env.sh` first (Nix store toolchain, builds on cores 1-11).

```bash
. ./env.sh && cb build --release                 # binary: target/release/bash-suggest
. ./env.sh && cb test                            # all tests
. ./env.sh && cb test --test e2e                 # end to end only
. ./env.sh && cb test --bin bash-suggest keys    # unit tests matching "keys"
. ./env.sh && cb test --release --bin bash-suggest bench_50k -- --ignored --nocapture
```

`init.bash` uses the release binary: rebuild release after changes, new terminals pick it up.

## Config and files

- Install: last line of `~/.bashrc` is `source ~/syshelp/bash-suggest/init.bash`. Backup: `~/.bashrc.bak-pre-bash-suggest`.
- Env: `BASH_SUGGEST` (set = do not wrap; `1` = inner shell), `BASH_SUGGEST_BIN`, `BASH_SUGGEST_FAIL` (test: force plain-bash fallback).
- Per shell: `$XDG_RUNTIME_DIR/bash-suggest.<bash pid>.names` (aliases+functions) and `.env` (HISTFILE, PATH), removed on exit.

## Safety rules

- **Never break the plain-bash fallback in `main.rs`/`init.bash`.** The wrapper is exec'd from every new terminal; a crash there locks the user out of shells.
- **Keep `PROMPT_COMMAND` a string when it is one.** Arrays are not exported; child programs (zoxide) lose the hook.
- **No terminal emulation outside the prompt, no timers while idle.** CPU budget: 0% idle, < 2 ms per key at 50k history lines. Re-run `bench_50k` after touching `suggest`/`sources`/`fuzzy`.
- **Never run user programs to learn suggestions** (no `cmd --help`).
- **Test GUIs only in a hidden virtual screen** (`hidden-gui` skill), never on the live desktop; prefer the e2e tests.

## Style

- TDD: a failing test first, including e2e for behavior changes.
- Few crates: rustix, libc, memchr, vt100. Add one only with a clear reason.
- Keep pure logic (keys, render, suggest, screen) free of I/O so it stays unit-testable.

## Companion docs

- `DESIGN.md`: intent, goals, anti-goals, CPU budget. Read before changing behavior.
- `PLAN.md`: original build plan and review amendments (history; code wins where they differ).
- `README.md`: user-facing install, keys, limits.
