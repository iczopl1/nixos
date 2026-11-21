# bash-suggest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rust PTY wrapper that gives bash gray ghost suggestions and a fuzzy list under the prompt, installed by one `source` line.

**Architecture:** `bash-suggest` execs from `init.bash`, runs `bash -i` in a pty, scans bash output for OSC 133 markers, mirrors the screen in a `vt100` parser to read the typed line, and draws/erases suggestions around forwarded keys. Pure logic (fuzzy, sources, keys, render) is separate from the I/O loop so it is unit-tested.

**Tech Stack:** Rust stable (edition 2021), crates `rustix` (features `pty`, `termios`, `process`, `fs`, `event`, `stdio`) and `vt100` 0.15. No other runtime crates. Dev: `tempfile`.

**Spec:** `~/syshelp/bash-suggest/DESIGN.md`

## Global Constraints
- Release binary under ~1 MB (`opt-level="s"`, `lto=true`, `strip=true`, `panic="abort"` NOT used: terminal restore needs unwind).
- < 2 ms work per keystroke for 50k history lines. 0% CPU idle.
- CPU budget section of DESIGN.md is binding: no emulation outside prompt, memchr marker scan, incremental history, recompute only on line change, char-bitmask prefilter.
- Extra crate allowed: `memchr`.
- Never run user programs to learn suggestions.
- Active only between OSC `133;B` and `133;C`, never on the alt screen.
- Install = `source ~/syshelp/bash-suggest/init.bash`; does nothing if not interactive, no tty, `BASH_SUGGEST` set, or binary missing.
- Max 8 list rows. Ghost = dim (`\e[2m` or 90 gray), selected row = reverse.
- Tests of terminal behavior run only in a hidden virtual screen (`hidden-gui` skill), never on the live desktop. Apps launched from Claude's shell use `env LD_LIBRARY_PATH=/etc/sane-libs`.

## Review Focus
1. Bracketed paste (`\e[200~`...`\e[201~`): Tab/arrows inside it go to bash untouched, no redraw until paste end.
2. Prompt on the last screen row: list scrolls the screen up first, prompt stays intact, no leftover rows after Enter.
3. Typed line longer than terminal width (wraps) and PS2 continuation lines: line extraction is correct or suggestions hide; never garbage.
4. Ctrl-C / Ctrl-D / resize while the list is shown: list erased, size forwarded, wrapper exits with bash's exit code.
5. Nested shells (`bash`, `tmux`, `ssh` inside wrapper): `BASH_SUGGEST=1` is exported, so inner bash does not wrap again but still prints markers.

## Review amendments (binding; override task text where they conflict)
Each line names its owning task; that task adds the listed test.
- **T4 lockout:** if openpt/spawn fails, wrapper restores tty and `execvp("bash", ["bash","-i"])` with `BASH_SUGGEST=1` (plain shell survives). Panic hook restores tty and SIGHUPs bash. Test: force spawn failure via env `BASH_SUGGEST_FAIL=1` → plain bash runs `echo ok`.
- **T4 process:** spawn via `std::process::Command::pre_exec` (setsid, `TIOCSCTTY` via rustix ioctl); master opened `RDWR|NOCTTY|CLOEXEC`. Self-pipe for SIGWINCH, SIGHUP, SIGTERM; on HUP/TERM send it to bash's pgrp. Retry on EINTR. On EIO drain master, `waitpid`, exit with code or 128+signal. Tests: `exit 3` → 3, `kill -9 $$` → 137, `exec true` → 0. Tests use an in-process pty harness (same pty module), not `script`.
- **T7 markers only from our bash:** act on a marker only if `tcgetpgrp(master) == bash pid` (checked once per marker). Nested bash/tmux/ssh markers are ignored; nested shells get no suggestions (documented).
- **T5 cursor seed:** `Screen::start` feeds `\e[{r};{c}H` to a fresh `vt100::Parser::new(rows, cols, 0)`. Scroll handling: builder verifies the vt100 0.15 API; if no scroll signal exists, count scrolls by pre-scanning fed bytes for LF/IND/NEL while the parser cursor is on the last row, and shift `input_start` up. Test: wrapped line typed on the bottom row.
- **T5/T7 cursor query (`ESC[6n`):** sent once after `133;B`. Stdin parser for `ESC [ digits ; digits R` works over split reads and runs only while a query is outstanding (so Ctrl-F3 `ESC[1;5R` is not eaten otherwise). Non-matching bytes forwarded in order. No reply in 50 ms → suggestions off for this prompt. Never blocks the loop. Tests: reply split, late, never.
- **T7 redisplay race:** on any master output while something is drawn: erase first, then write bash output, then re-arm settle. Erase = move to row below cursor + `\e[J` + clear ghost with `\e[K`.
- **T5 flicker:** each draw/erase built into one `Vec` and sent in one `write`, wrapped in `\e[?2026h`…`\e[?2026l`. Use relative moves (CUU/CUD/CHA) from the known cursor, not `\e7/\e8`. Test: ghost when cursor is at the last column → hide ghost (no wrap).
- **T6 Esc:** in list mode only, a read ending in lone `ESC` is held ≤ 25 ms; outside list mode ESC is forwarded at once (readline latency unchanged).
- **T6 accept (replaces Ctrl-E/Ctrl-U):** list accept only when cursor is at end of line: send `\x7f` × (chars after common prefix), then the rest as bracketed paste `\e[200~…\e[201~` if bash enabled `?2004h` (tracked from output), else raw. Works in emacs and vi insert mode. Reject items with control chars or `\n`. Ghost accept sends only the suffix the same way.
- **T6 split input:** `Keys` keeps a carry buffer for incomplete escape sequences; test every split offset of `\e[C`, `\e[Z`, `\e[200~`.
- **T3/T7 CPU:** `Scanner` yields via callback over the 64 KB read buffer, no per-read `Vec`. Sources stat'ed only on `133;A`, not per keystroke. Names file read only when its mtime changed.
- **T3/T2 history path:** init.bash writes `$HISTFILE` (or empty) next to the names file; wrapper falls back to `~/.bash_history`; missing file → empty history, no error. Load at most last 100k lines; `lower: Box<str>`.
- **T5 wide chars:** if the typed line has non-ASCII or a wide-continuation cell, hide suggestions. Test with `echo ü`.
- **Cargo:** `opt-level=3` (CPU beats size); drop the 1 MB size goal if it conflicts.
- **T3 tests:** `env BASH_SUGGEST=1 bash -i -c 'echo ok'` with init.bash sourced does not exec.

---

### Task 1: Scaffold + fuzzy scorer

**Files:** Create `Cargo.toml`, `src/main.rs` (stub), `src/fuzzy.rs`; `git init`.

**Interfaces:**
- Produces: `pub fn score(query: &str, cand: &str) -> Option<i32>` (None = no match; higher = better).

- [ ] Step 1: Tests in `src/fuzzy.rs`:
  - `score("gco","git checkout")` is Some; `score("xyz","git")` is None.
  - Case-insensitive: `score("GIT","git")` is Some.
  - Word-start beats middle: `score("gc","git commit") > score("gc","logcat")`.
  - Consecutive beats scattered: `score("com","commit") > score("com","cargo build -m")`.
  - Shorter wins on tie: `score("ls","ls") > score("ls","lsblk")`.
- [ ] Step 2: `cargo test fuzzy` fails.
- [ ] Step 3: Implement greedy-forward subsequence then backward tighten (fzf v1). Points: +16 per char, +8 boundary (start or after ` /-_.`), +4 consecutive, −1 per gap char, −len/8.
- [ ] Step 4: `cargo test fuzzy` passes.
- [ ] Step 5: Commit.

### Task 2: Sources + ranking

**Files:** Create `src/sources.rs`, `src/suggest.rs`.

**Interfaces:**
- Consumes: `fuzzy::score`.
- Produces:
  - `pub struct History { pub fn load(path:&Path)->Self; pub fn refresh_if_changed(&mut self); }` (dedup newest-wins, keeps count + last index; handles `#<timestamp>` lines).
  - `pub fn path_commands(path_var:&str)->Vec<String>`; `pub fn read_names(file:&Path)->Vec<String>` (aliases/functions dump, one per line).
  - `pub fn list_dir(cwd:&Path, typed:&str, max:usize)->Vec<String>` (dirs end in `/`, hidden files only if typed basename starts with `.`).
  - History keeps `offset: u64`; `refresh_if_changed` reads only bytes after offset (full reload if file shrank). Each entry stores `lower: String` and `mask: u64` (bit per a-z0-9 + few symbols) for prefilter.
  - Test: append a line to the file, refresh, new line present and old counts unchanged; truncate file → full reload.
  - `pub fn subcommands(h:&History, cmd:&str)->Vec<String>` (word 2 of lines whose word 1 == cmd, by count).
  - `pub struct Ctx<'a>{history:&'a History, commands:&'a [String], cwd:&'a Path}`
  - `pub struct Suggestion{ pub text:String /*full new line*/, pub ghost:Option<String> }`
  - `pub fn suggest(line:&str, ctx:&Ctx, max:usize)->Vec<Suggestion>`
- [ ] Step 1: Tests (tempdir fixtures):
  - History file `["ls","git status","git push","git status"]` → `suggest("git s")` first = `"git status"`, ghost `Some("tatus")`.
  - `suggest("gst")` contains `"git status"` with `ghost == None` (fuzzy, not prefix).
  - Word 1 `"carg"` with commands `["cargo"]` and empty history → `"cargo"`.
  - `suggest("cd sr")` in dir with `src/` → `"cd src/"`.
  - `subcommands(h,"git")` == `["status","push"]`.
  - Empty line → empty vec. Result length ≤ max, no duplicate `text`.
- [ ] Step 2: Fail. Step 3: Implement; rank = fuzzy score + 2·ln(count) + recency bonus (top 100 lines +5). History lines first, then commands/subcommands/files. Step 4: Pass. Step 5: Commit.

### Task 3: Markers + init.bash

**Files:** Create `init.bash`, `src/markers.rs`.

**Interfaces:**
- Produces: `pub enum Mark{PromptStart, InputStart, CmdStart}`; `pub struct Scanner; impl Scanner{ pub fn feed(&mut self, buf:&[u8]) -> Vec<Chunk> }` where `enum Chunk<'a>{Bytes(&'a [u8]), Mark(Mark)}`. Handles a marker split across two reads. Recognizes `\e]133;A\a`, `;B`, `;C`, BEL or `\e\\` ending. Markers are still passed to the terminal (harmless).
- [ ] Step 1: Tests: single buffer with A..B; marker split at every byte offset; ST terminator; unrelated OSC (`\e]0;title\a`) passes as bytes.
- [ ] Step 2: Fail. Step 3: Implement. Step 4: Pass.
- [ ] Step 5: `init.bash`:
  - Outer: `[[ $- == *i* && -t 0 && -t 1 && -z $BASH_SUGGEST ]] && command -v <bin> >/dev/null && exec <bin>` where `<bin>` = `$BASH_SUGGEST_BIN` or `~/syshelp/bash-suggest/target/release/bash-suggest`.
  - Inner (`BASH_SUGGEST=1`): wrap PS1 as `\[\e]133;A\a\]$PS1\[\e]133;B\a\]` at each prompt (via PROMPT_COMMAND function, so later PS1 changes survive); `PS0+='\e]133;C\a'`; `history -a`; write `compgen -a; compgen -A function` to `$XDG_RUNTIME_DIR/bash-suggest.$$.names`; remove it on EXIT.
  - Test: `bash -n init.bash`; `BASH_SUGGEST=1 bash --rcfile init.bash -i <<<'echo ok'` prints markers (check with `cat -v`).
- [ ] Step 6: Commit.

### Task 4: PTY relay (no drawing)

**Files:** Create `src/pty.rs`, `src/term.rs`; modify `src/main.rs`.

**Interfaces:**
- Produces: `pub struct Child{ pub master: OwnedFd, pub pid: Pid }`; `pub fn spawn_bash(size: Winsize) -> io::Result<Child>` (openpt/grantpt/unlockpt, child: setsid, `TIOCSCTTY`, dup2 slave, `exec $SHELL`-independent `bash -i`, env `BASH_SUGGEST=1`); `pub struct RawGuard` (sets raw mode on stdin, restores on Drop and on panic hook); `fn winsize() -> Winsize`.
- Main loop: `poll` on stdin, master, and a self-pipe written by SIGWINCH handler. Exit when master read gives EIO/0; return bash's exit status via `waitpid`.
- [ ] Step 1: Integration test `tests/relay.rs`: run binary under `script -qec` with input `echo hi\nexit 3\n`; assert output contains `hi` and exit code 3.
- [ ] Step 2: Fail. Step 3: Implement. Step 4: Pass. Step 5: Commit.

### Task 5: Screen mirror + render

**Files:** Create `src/screen.rs`, `src/render.rs`.

**Interfaces:**
- Produces: `pub struct Screen{ parser: Option<vt100::Parser> /*Some only at prompt*/, input_start: Option<(u16,u16)> }` with `start(&mut self, cursor:(u16,u16), size)` (called after the `ESC[6n` reply following `133;B`; main intercepts `ESC[r;cR` from stdin and does not forward it), `stop()` on `133;C`, `feed(&mut self, bytes)` (no-op when parser is None), `pub fn current_line(&self) -> Option<(String, usize /*cursor col in line*/)>` (None when inactive, alt screen, or cursor row/col before input_start; joins wrapped rows), `resize(rows, cols)`.
- `pub struct Drawn{ rows_below: u16, ghost_len: u16 }`; `pub fn draw(out:&mut Vec<u8>, ghost:Option<&str>, items:&[String], selected:Option<usize>, cursor:(u16,u16), size:(u16,u16)) -> Drawn`; `pub fn erase(out:&mut Vec<u8>, d:&Drawn, cursor:(u16,u16))`. Draw uses `\e7`/`\e8` save/restore; if not enough rows below, emit `\n`×k then cursor up k first (and tell Screen it scrolled). Items truncated to width−1.
- [ ] Step 1: Tests: feed `"\e]133;B\a" + "git st"` → `current_line == ("git st",6)`; alt screen (`\e[?1049h`) → None; after `133;C` → None; wrapped 100-char line on 80 cols round-trips. Render: draw at bottom row emits scroll; erase output clears exactly `rows_below` rows (`\e[2K`) and `ghost_len` cells (`\e[K`).
- [ ] Step 2: Fail. Step 3: Implement. Step 4: Pass. Step 5: Commit.

### Task 6: Key state machine

**Files:** Create `src/keys.rs`.

**Interfaces:**
- Produces: `pub enum Action{ Forward(Vec<u8>), Redraw, Accept(String) /*full line*/, AcceptGhost(String) /*suffix*/, Hide }`; `pub struct Keys{ list_mode: bool, sel: usize, in_paste: bool }`; `pub fn handle(&mut self, input:&[u8], has_items:bool, has_ghost:bool, at_eol:bool, n_items:usize) -> Vec<Action>`.
- Rules (spec): Right (`\e[C`/`\eOC`) at eol with ghost → AcceptGhost; Tab with items → enter list / next; Shift-Tab `\e[Z` → prev; Up/Down only in list mode; Enter in list mode → Accept(item), leave list mode; Esc (lone `\e`, decided after 5 ms by caller) → leave list mode; everything else → Forward + leave list mode. Tab without items → Forward. Inside bracketed paste → Forward only.
- Accept sent to bash as `\x05\x15` + text (Ctrl-E, Ctrl-U); AcceptGhost as the suffix bytes.
- [ ] Step 1: Tests for each rule above plus a paste containing `\t` and `\e[C`.
- [ ] Step 2: Fail. Step 3: Implement. Step 4: Pass. Step 5: Commit.

### Task 7: Wire up, verify, README

**Files:** Modify `src/main.rs`; create `README.md`.

- [ ] Step 1: Loop: on stdin → erase drawn → `Keys::handle` → write to master. On master output → write to stdout; scan with `Scanner` (memchr for `\x1b`); feed Screen only while at prompt; arm 5 ms settle timer only while at prompt. On settle and `current_line` is Some and line != last line → refresh sources (mtime check) → `suggest` → `draw`. Poll timeout is infinite when no redraw pending. Erase on SIGWINCH, then forward size.
- [ ] Step 1b: CPU check: `yes | head -c 200M > /dev/null`-style test inside wrapper: `time cat bigfile` through wrapper vs plain `script`, overhead < 10%. Idle wrapper shows 0.0% in `top -b -n 3 -p <pid>`.
- [ ] Step 2: `cargo build --release`; check size `< 1 MB`; bench `suggest` on 50k-line history `< 2 ms` (simple `#[test] #[ignore]` timing).
- [ ] Step 3: Manual check in hidden virtual screen (`hidden-gui` skill, foot or xterm in Xvfb, `env LD_LIBRARY_PATH=/etc/sane-libs`): ghost after `git s`, list, Tab/Enter, Right, paste, prompt at bottom, Ctrl-C, `vim` (nothing drawn), resize. Screenshot each.
- [ ] Step 4: README: install line, off switch `BASH_SUGGEST=0 bash`... note: `BASH_SUGGEST` non-empty disables wrap; keys table.
- [ ] Step 5: Commit.
