# Clev AI

AI-driven desktop navigation for Hyprland:
- **Claude** plans each step.
- **Jev** makes the quick picks over text: which element a description means (Choice), and yes/no checks (Noul). It runs as `typesafe/jev-1.14` through OpenRouter's `/api/alpha/decisions`, at about 0.3 s and $0.00002 per call.
- **Only Claude and Jev.** Never call chat models (`/chat/completions`, `jev-router`, which hands requests to third-party LLMs). Jev on OpenRouter ignores images, so screenshots are read by the driving Claude.
- **Executor:** `clev.py`.

## Rules
- **Targets:** use the app's AT-SPI tree first, since browsers, GTK, Qt, LibreOffice and Electron apps expose clickable fields. Fall back to the existing SUPER+D overlay (`~/syshelp/hint-click.sh` with the patched `wl-kbptr`) only for apps that expose nothing. Don't write new detectors.
- **CPU:** keep it light. Use no daemons. Block on the Hyprland event socket or the FIFO instead of polling. Use one AT-SPI Collection call instead of a tree walk where the app supports it. Take screenshots only on the fallback path.
- **System config:** `clev.nix` and `clev.conf` are copies for the user to review. Never put them into the system config yourself.
- **Jev key:** `$OPENROUTER_API_KEY`, else `~/.config/openrouter/key`.
- **Never sends:** in messaging apps (`CHAT_APPS`: Discord, Signal, Slack, Telegram, Element, WhatsApp, Teams, mail clients) clev types a draft but never presses Enter or a Send button; the user does.
- **Validate:** check every Jev answer in code. Ids must be in the list, and a pick is acted on only when its top probability is at least `CLEV_SURE` (0.6). Labels from Claude must match `label_symbols`, and the overlay must find the same target count again.

## Request flow (`clev do "<request>"`, used by SUPER+SHIFT+D)
1. **Jev fast path:** one Jev request picks a function plus its arguments (about 0.4 s).
   - The functions cover volume, brightness, keyboard light, Bluetooth, battery, workspaces and window state, web (a site from `SITES`, opened through its search URL or front page), app (launch, then type or `run`), terminal (a read-only `TERM_CMDS` template), read (a second Jev call picks the visible line that answers, e.g. a chat's last reply; reported verbatim), and chat.
   - **Chat:** clear small talk (function `chat` at p ≥ 0.8) opens an interactive `claude --model haiku --effort low` session in Alacritty with the request as its first message.
   - **Commands:** `term` runs in the background in the user's interactive `$SHELL` (aliases work), waits up to 10 s, and the output becomes the notification; a longer command keeps running detached (output in `$XDG_RUNTIME_DIR/clev/term/`). Only a request matching `IN_TERMINAL` ("in terminal", "in alacritty") gets `--show`, a visible Alacritty window.
   - Arguments are selected, never generated: text spans of the request, paths, numbers, windows, apps.
2. **Claude:** otherwise one Claude turn (`PLANNER.md`, no tools) writes a plan (launch, run, term, type, key), which clev executes in-process.
3. **Full driver:** if a step fails, `clev-goal.sh` hands over to the full Claude driver (`DRIVER.md`).
4. **Decision cache:** confident device and window decisions are kept in `~/.cache/clev/decisions.json`, so repeating a request needs no network (about 0.1 s).
5. **Memory (teaching on the fly):** a request starting with `remember:`, `r:`, `remember that`, `note:`, `teach:`, `learn:` or `from now on` is stored as a lesson and nothing else runs; `forget: <words>` or `forget <n>` removes one.
   - Lessons live in `~/.config/clev/memory`, one per line (hand-editable, at most 50; `CLEV_MEMORY` overrides the path). Also `clev teach|memory|forget`.
   - They go to the Jev router as `user_notes` (and their addresses and existing paths become candidates), to the planner as `memory`, to the full driver appended to the goal, and to `run` steps when they mention that app or site.
   - Before `run`/`fill` types into a field, a lesson for that app (for a browser, also lessons about the browser or web pages) can name a key to press first, such as Vimium's `[i]`. Only keys written in the lesson are candidates, and Jev picks one (sure picks only). `ctrl+a` follows, so a key that lands in the field is replaced.
   - Cached decisions carry a hash of the lessons, so teaching anything invalidates them. With no lessons every request is exactly as before.
   - Only the user writes memory: `teach`/`forget` refuse under `CLEV_DRIVER`, and plans and driver tools can't reach them. Lessons never lift a confirmation or `CLEV_SURE`.

## Files
- `clev.py`: the CLI. Run `clev -h` for the commands. `CLEV_DRY=1` resolves targets without doing any input, and `CLEV_DUMP=1` writes each `run` step's Jev request to `$XDG_RUNTIME_DIR/clev/stepN.json`.
- `PLANNER.md`: the system prompt for the one-turn Claude planner.
- `tests/suite.py <store path> [ids]`: the 25 timed, non-destructive tests.
  - Each test is judged by a ground-truth check, against a human baseline from the Keystroke-Level Model.
  - Each test restores what it changed and closes the Firefox tabs it opened.
  - `tests/report.py` prints the results table.
  - The suite runs with `CLEV_MEMORY=/dev/null`, so the user's lessons don't change the benchmark.
- `clev-goal.sh`: SUPER+SHIFT+D asks for a goal and runs headless `claude -p` with `DRIVER.md`. Its last notification adds a `$` summary: total, Claude (planner + driver), Jev calls and cost, seconds (also written to `last-run.jsonl` as `spent`).
- `DRIVER.md`: the instructions Claude follows while operating the desktop. To operate the desktop from an interactive session, follow DRIVER.md.

## Testing without installing
```sh
nix-shell -p 'python3.withPackages (p: [ p.pygobject3 ])' at-spi2-core gobject-introspection wtype grim
CLEV_DRY=1 python3 clev.py tree
```
Firefox and Qt apps expose their trees live once `org.a11y.Status.IsEnabled` is true; clev sets it. GTK apps need `NO_AT_BRIDGE` unset at launch.
