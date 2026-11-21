# clev-goal: ask for a goal (wofi), let headless Claude reach it with clev.
#   clev-goal ["goal text"]     no argument -> wofi prompt
# Progress shows as one updating notification. SUPER+SHIFT+Escape (clev stop)
# kills the whole run: this script re-execs as its own process group for that.
# The run's timestamped event stream is kept in $XDG_RUNTIME_DIR/clev/last-run.jsonl.

run_dir="${XDG_RUNTIME_DIR:?}/clev"
mkdir -p "$run_dir" && chmod 700 "$run_dir"

if [[ "$(ps -o pgid= -p $$ | tr -d ' ')" != "$$" ]]; then
  exec setsid "$0" "$@"
fi

goal="${1:-}"
if [[ -z "$goal" ]]; then
  goal=$(wofi --dmenu --prompt "What should I help with?" --lines 1 </dev/null) || exit 0
fi
[[ -n "$goal" ]] || exit 0

pidfile="$run_dir/driver.pid"
if [[ -e "$pidfile" ]] && grep -qs clev-goal "/proc/$(cat "$pidfile")/cmdline"; then
  notify-send -a clev "Clev AI busy" "A goal is already running (SUPER+SHIFT+Escape stops it)" || true
  exit 1
fi
echo $$ >"$pidfile"
printf '%s' "$goal" >"$run_dir/goal"  # shown by the waybar pill
trap 'rm -f "$pidfile" "$run_dir/goal"' EXIT

# The first notification is sent in the background so the request starts at once.
notify-send -p -a clev -t 0 -- "Clev AI" "$goal" >"$run_dir/nid" 2>/dev/null &
note_pid=$!
note() {  # the body can be command output: no option parsing, no markup
  wait "$note_pid" 2>/dev/null || true
  local body="${1//&/&amp;}" category=()
  [[ -n "${3:-}" ]] && category=(-c "$3")
  body="${body//</&lt;}"
  notify-send -r "$(cat "$run_dir/nid" 2>/dev/null || echo 0)" -a clev "${category[@]}" -t "${2:-0}" -- "Clev AI" "${body//>/&gt;}" >/dev/null || true
}

# Driver instructions live next to the real script (installed via the nix module).
driver_md="${CLEV_DRIVER_MD:-@driver_md@}"

# The driver works by description (Jev decides; no `tree` dumps), may never use
# `answer`/`stop` (the user's), and may only Read the screenshots in $run_dir.
allowed=(Read"(/$run_dir/**)")
for sub in run launch term next wait click fill ask read shot hint type key scroll windows focus confirm; do
  allowed+=("Bash(clev $sub:*)")
done
allowed+=("Bash(clev -h)" "Bash(clev --help)")  # harmless; saves a denied first step

export CLEV_DRIVER=1
rm -f "$run_dir/pinned" "$run_dir/hints.json"
cd "$run_dir" || exit 1
: >"$run_dir/last-run.jsonl"
t_start=$(date +%s.%3N)
driver_usd=0

# "$ summary" for the final notification: what this run spent and how long it
# took. Jev and planner costs come from the log lines clev wrote since the
# start; the full driver's Claude cost from its result line.
spent() {
  local sums
  sums=$(tail -n 300 "$run_dir/log.jsonl" 2>/dev/null | jq -rs --argjson t0 "$t_start" '
    map(select(.t >= $t0)) as $l | [$l[].jev[]?] as $j
    | "\([$j[].cost | numbers] | add // 0) \($j | length) \([$l[].claude_usd | numbers] | add // 0)"') \
    || sums="0 0 0"
  awk -v s="$sums $driver_usd $t_start $(date +%s.%3N)" 'BEGIN {
    split(s, v, " "); claude = v[3] + v[4]
    printf "%s  ·  Claude %s  ·  Jev %d× %s  ·  %.1f s", usd(v[1] + claude), usd(claude), v[2], usd(v[1]), v[6] - v[5]
  }
  function usd(x,  d) {  # two significant digits, at least cents
    if (x <= 0) return "$0"
    d = 2 - int(log(x) / log(10)); if (d < 2) d = 2
    return sprintf("$%." d "f", x)
  }'
}
# Played when a run ends (done or stopped). Backgrounded so the notification isn't held up.
sound="${CLEV_SOUND:-@sound@}"
chime() { [[ -r "$sound" ]] && { pw-play "$sound" >/dev/null 2>&1 & } || true; }

finish() {  # the last notification, with the summary; also kept in last-run.jsonl
  local sum
  chime
  sum=$(spent)
  printf '{"t":%s,"spent":%s}\n' "$(date +%s.%3N)" "$(jq -Rn --arg s "$sum" '$s')" >>"$run_dir/last-run.jsonl"
  note "$1"$'\n'"$sum" "$2" clev.done  # category: the only notification mako styles specially
}

# Fast path: Jev alone (hardware, windows), else one Claude turn writes a plan
# that clev executes. Only if that stops does the full Claude driver below run.
quick=$(clev "do" "$goal" 2>/dev/null | tail -1 || true)
printf '{"t":%s,"do":%s}\n' "$(date +%s.%3N)" "${quick:-null}" >>"$run_dir/last-run.jsonl"
if [[ "$(jq -r '.ok' <<<"$quick" 2>/dev/null)" == "true" ]]; then
  finish "$(jq -r '.say // "done"' <<<"$quick")" 8000
  exit 0
fi
handoff=$(jq -r '.handoff // false' <<<"$quick" 2>/dev/null || true)
[[ -z "$quick" || -z "$handoff" ]] && handoff=true  # crashed or no JSON: let the driver try
if [[ "$handoff" != "true" ]]; then
  finish "$(jq -r '.error // "stopped"' <<<"$quick" 2>/dev/null || echo stopped)" 15000
  exit 1  # e.g. denied by the user: don't work around it
fi
stopped_at=$(jq -c '{error, steps}' <<<"$quick" 2>/dev/null || true)
goal_for_driver="$goal"$'\n\n'"(A quick attempt stopped: ${stopped_at:0:600}. Continue from the current screen.)"
taught=$(clev memory 2>/dev/null | jq -r '.lessons[]? | "- " + .lesson' 2>/dev/null || true)
[[ -n "$taught" ]] && goal_for_driver+=$'\n\n'"(The user taught you:"$'\n'"$taught)"
result=""
while IFS= read -r line; do
  printf '{"t":%s,"e":%s}\n' "$(date +%s.%3N)" "$line" >>"$run_dir/last-run.jsonl"
  case "$line" in
    *'"type":"assistant"'*)
      step=$(jq -r '.message.content[]? | select(.type=="tool_use") | .input.command // .input.file_path // empty' <<<"$line" 2>/dev/null | head -1 || true)
      [[ -n "$step" ]] && note "$goal"$'\n'"› ${step:0:120}"
      ;;
    *'"type":"result"'*)
      result=$(jq -r '.result // .error // "done"' <<<"$line" 2>/dev/null || true)
      driver_usd=$(jq -r '.total_cost_usd // 0' <<<"$line" 2>/dev/null || echo 0)
      ;;
  esac
done < <(env -u OPENROUTER_API_KEY claude -p \
  --model "${CLEV_CLAUDE_MODEL:-haiku}" \
  --permission-mode dontAsk \
  --strict-mcp-config \
  --setting-sources "" --disable-slash-commands \
  --allowedTools "${allowed[@]}" \
  --append-system-prompt-file "$driver_md" \
  --output-format stream-json --verbose \
  -- "$goal_for_driver" </dev/null 2>/dev/null)

finish "${result:-stopped}" 15000
