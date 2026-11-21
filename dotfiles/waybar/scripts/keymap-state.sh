#!/usr/bin/env bash

set -u

SUBMAP=reset
MODE="${1:-keymap}"   # keymap | nosleep: one dot per module so each takes its own click

# Filled dot = on, empty dot = off. keymap: off in the "clean" submap.
# nosleep: the `nosleep` alias holds a lid-switch inhibitor until the next lid
# close/open cycle finishes.
print_state() {
  [ $# -gt 0 ] && SUBMAP="$1"
  local dot="●" name="on" label="SUPER+TAB keymap" class="on"

  if [ "$MODE" = nosleep ]; then
    label="nosleep (skip next lid close)"
    if ! systemd-inhibit --list --no-legend 2>/dev/null | grep -q "skip next lid close"; then
      dot="○"; name="off"; class="off"
    fi
  elif [ "$SUBMAP" = "clean" ]; then
    dot="○"; name="off"; class="off"
  fi

  printf '{"text":"%s","class":"%s","tooltip":"%s: %s (click to toggle)"}\n' "$dot" "$class" "$label" "$name"
}

# Waybar stops a module by signalling this shell alone; take the socat pipeline
# down with it, or every waybar restart leaves one listening on the Hyprland
# socket. Waybar starts each module in its own process group, so `kill 0`
# reaches only this script's processes.
trap 'trap - TERM INT HUP PIPE EXIT; kill 0 2>/dev/null' TERM INT HUP PIPE EXIT

# Waybar does not always signal its modules on the way out; reparenting is the
# one sign that never fails, so the wait loop below checks for it.
read -r _ _ _ parent _ < /proc/$$/stat
orphaned() {
  local ppid
  read -r _ _ _ ppid _ < /proc/$$/stat
  [ "$ppid" != "$parent" ]
}

print_state reset

if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
  while ! orphaned; do
    mmsg watch keymode | while :; do
      IFS= read -r -t 2 line
      status=$?
      [ "$status" -gt 128 ] && { print_state; continue; }
      [ "$status" -ne 0 ] && break
      mode=$(jq -r .keymode <<<"$line")
      [ "$mode" = default ] && mode=reset
      print_state "$mode"
    done &
    pipeline=$!
    while kill -0 "$pipeline" 2>/dev/null; do
      orphaned && exit 0
      sleep 3 & wait $!
    done
    sleep 1
  done
  exit 0
fi

if ! command -v socat >/dev/null 2>&1; then
  while ! orphaned; do
    sleep 2
    print_state
  done
  exit 0
fi

while :; do
  socket_path="${XDG_RUNTIME_DIR:-}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"

  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -S "$socket_path" ]; then
    sleep 2
    orphaned && exit 0
    continue
  fi

  socat -U - UNIX-CONNECT:"$socket_path" 2>/dev/null | while :; do
    # the timeout re-polls the nosleep inhibitor, which emits no event
    IFS= read -r -t 2 event
    status=$?
    [ "$status" -gt 128 ] && { print_state; continue; }
    [ "$status" -ne 0 ] && break
    case "$event" in
      submap'>>'*)
        print_state "${event#submap>>}"
        ;;
    esac
  done &
  # in the background, so a signal reaches the trap at once (bash holds a trap
  # until a foreground pipeline ends), and so the orphan check can run
  pipeline=$!
  while kill -0 "$pipeline" 2>/dev/null; do
    orphaned && exit 0
    sleep 3 & wait $!
  done

  print_state reset
  sleep 1
done
