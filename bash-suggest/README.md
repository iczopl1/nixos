# bash-suggest

Fish-like suggestions for bash: gray ghost text after the cursor and a fuzzy
list under the prompt. Small Rust wrapper; bash and readline stay unchanged.

## Install

```bash
. ./env.sh && cargo build --release     # env.sh puts rustc on PATH (NixOS)
```

Add as the LAST line of `~/.bashrc`:

```bash
source ~/syshelp/bash-suggest/init.bash
```

New terminals get it. If the binary is missing or broken, you get a plain bash.

- Off for one shell: `BASH_SUGGEST=0 bash`
- Other binary path: `BASH_SUGGEST_BIN=/path/to/bash-suggest`

## Keys

| Key | Does |
|-----|------|
| Right arrow (at end of line) | accept next word of the gray ghost text (space, `/` and `.` end a word) |
| Tab | open list / next item (no suggestions: normal bash completion) |
| Shift-Tab | previous item |
| Up / Down | move in list (only while list is open) |
| Enter (list open) | put item on the line, does not run it |
| Esc | close list |

## Sources

History lines (fuzzy + prefix, frequency, recency), commands in PATH,
aliases and functions, subcommands learned from your history, files in bash's
current directory. Nothing runs other programs to learn suggestions.

## Limits

- Suggestions only with the cursor at end of line, ASCII text, single-line input.
- Nested shells (bash in bash, tmux, ssh) get no suggestions inside.
- After a window resize, suggestions return at the next prompt.
- The terminal must answer the cursor-position query (`ESC[6n`); all common ones do.

## Cost

- Idle: no CPU, no timers.
- While commands print: bytes are copied once more and scanned for markers only.
- Per keystroke: < 2 ms with 50k history lines (`cargo test --release bench_50k -- --ignored --nocapture`).

## Tests

```bash
. ./env.sh && cargo test      # unit + pty relay + end-to-end on a private pty
```
