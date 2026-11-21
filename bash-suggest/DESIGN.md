# bash-suggest: design

## Intent
Live, fish-like suggestions for bash, written in Rust, as light as possible.
While typing at a bash prompt: a gray "ghost" completion after the cursor, and a
short fuzzy-matched list under the prompt. Bash itself stays unchanged.

## Goals
- Gray ghost text after the cursor; Right arrow accepts it one word at a time.
- Suggestion list fills every row below the prompt (at least 8; scrolls near the bottom), updated on every key.
- Fuzzy matching (fzf-style subsequence, bonus for word starts and adjacency).
- Sources: bash history, commands in PATH (+ aliases/functions), files/dirs, subcommands.
- Single static binary, no runtime daemon, under ~1 MB, < 2 ms per keystroke.

## Non-goals
- Replacing readline. All editing keys, Ctrl-R, vi mode, inputrc keep working.
- Shells other than bash.
- Per-tool argument specs (flags, option values).

## Anti-goals (failure even if it "works")
- Any visible lag or flicker while typing.
- Drawing anything inside full-screen apps (vim, less, htop) or while a command runs.
- Breaking paste, Ctrl-C, resize, or job control.
- Running arbitrary programs to learn suggestions.

## Approaches
1. **PTY wrapper (picked).** `bash-suggest` starts bash in a pseudo-terminal
   (pty), relays bytes both ways, and draws ghost text + list itself. Smooth,
   works for every key. Cost: one extra process per terminal, ~800 lines.
2. bind -x on every key, calling a Rust binary per keystroke. Smallest code, but
   a process spawn per key, flicker, broken paste speed. Rejected.
3. Own line editor replacing readline. Full control, but loses readline
   features. Rejected.

## How it works
- **Install = one line in `~/.bashrc`:** `source ~/syshelp/bash-suggest/init.bash`
  (put last). `init.bash` has two modes:
  - Outer shell (interactive, stdin is a tty, `BASH_SUGGEST` unset, binary
    found): `exec bash-suggest`. The wrapper sets `BASH_SUGGEST=1`, opens a pty
    and spawns `bash -i`, which reads `~/.bashrc` normally.
  - Inner shell (`BASH_SUGGEST=1`): add prompt markers (below) and `history -a`
    to `PROMPT_COMMAND`, dump aliases/functions each prompt.
  - Anything else (non-interactive, no tty, binary missing): do nothing, so a
    broken build never locks you out of a shell.
- **Prompt markers:** OSC 133 sequences (shell-integration standard): `A` before
  PS1, `B` after PS1 (input starts), `C` in a `PS0` (command starts).
  Suggestions are active only between `B` and `C`, and never on the alt screen.
- **Knowing the typed line:** bash output is fed into an in-memory terminal
  (`vt100` crate). The current line = screen text from the `B` position to the
  end of input, cursor from the emulator. So any readline edit (Ctrl-W, history
  Up, Tab completion) is seen correctly with no key-tracking guesswork.
- **Drawing:** after bash's output settles (no bytes for ~5 ms), draw ghost text
  in dim gray after the cursor and the list below, using save/restore cursor.
  At the bottom of the screen, scroll up to reserve rows first. Before any key
  is forwarded to bash, erase what was drawn. Clear everything on Enter.
- **Keys** (only while suggestions are shown, otherwise passed to bash):
  - Right arrow at end of line: accept the next word of the ghost text
    (space, `/` and `.` end a word).
  - Tab: enter list / next item. Shift-Tab: previous. Up/Down: move only while
    in list mode. Enter in list mode: put item on the line (does not run it).
    Esc: leave list mode.
  - Tab with no suggestions goes to bash (normal bash completion).
- **Accepting:** send the needed edit to bash as keystrokes so readline owns the
  buffer: backspaces for the differing tail, then the new text as plain keys
  (bracketed paste left it highlighted). Works in emacs and vi insert mode.
  Only at end of line.
- **Safety:** if the pty cannot be opened, the wrapper execs a plain `bash -i`.
  Markers are honored only while our bash is the foreground job.

## Sources and ranking
- Word 1: history lines (whole line), then PATH executables, aliases, functions.
- Later words: history lines with the same prefix, subcommands, files/dirs
  relative to the typed path.
- **History:** `$HISTFILE`, re-read when its mtime changes. Rank = fuzzy score +
  frequency + recency. Deduped.
- **PATH/aliases/functions:** PATH scanned on start and when `$PATH` dir mtimes
  change. Aliases/functions dumped by the init snippet to a temp file each prompt
  (`compgen -a`, `compgen -A function`).
- **Subcommands:** learned from history only: word 2 of past lines starting with
  the same command (e.g. `git` -> commit, push, status). No `--help` execution.
- **Files:** `read_dir` of the path being typed, max 500 entries, dirs get `/`.
- Ghost text = top suggestion only if it starts with the typed text (prefix);
  fuzzy-only matches appear in the list, not as ghost.

## Fuzzy matcher
Own ~80-line scorer: case-insensitive subsequence match, bonus for match at word
start / after `/ - _ .`, bonus for consecutive chars, small length penalty.
No external crate.

## Constraints
- Rust, minimal crates: `rustix` (pty, termios, signals) and `vt100`. No async runtime;
  one `poll` loop on stdin + pty master + SIGWINCH pipe.
- Terminal restored on any exit, including panic.
- Window resize forwarded to the pty and the emulator.
- Install is only the `source` line above. User adds it to `~/.bashrc` themselves.
- Off switch: `BASH_SUGGEST=0 bash` starts a plain shell.

## CPU budget (top priority)
- Idle = 0% CPU: blocking `poll`, no timers or polling unless a redraw is pending.
- While a command runs (between `C` and next `A`): bytes are only relayed and
  scanned for `ESC ] 133` with `memchr`. No terminal emulation. `cat` of a big
  file costs almost nothing extra.
- Emulation only at the prompt: on `B`, ask the real terminal for the cursor
  position (`ESC[6n`, reply intercepted from stdin), start a fresh one-screen
  `vt100` parser at that position, feed only prompt-time output to it.
- History read once, then only appended bytes (keep file offset; full reload
  only if file shrank). Candidates stored pre-lowercased.
- Recompute suggestions only when the typed line changed. Typing faster than
  the 5 ms settle delay does one recompute, not one per key.
- Fuzzy scan stops early: prefix matches checked first; skip scoring when the
  query's chars are not all present (byte bitmask per candidate).

## Left to the builder
- Exact settle delay, list height, colors (default: list dim, selected reversed).
- Structure of modules.
- Test approach: fuzzy scorer + source ranking as unit tests; terminal behavior
  tested in a hidden virtual terminal, never on the live desktop.
