#!/usr/bin/env bash

# This script manages a dynamic 80/20 window layout for two windows on a workspace.
# Focused window takes 80%, unfocused takes 20%. Toggles this behavior.

LAYOUT_STATE_FILE="/tmp/hypr_two_window_layout_enabled"
DAEMON_PID_FILE="/tmp/hypr_two_window_layout_daemon.pid"
HYPR_EVENT_SOCK="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

declare -A WINDOW_DATA # Associative array to store window details

# Function to get active workspace ID
get_active_workspace() {
  hyprctl activeworkspace -j | jq -r '.id'
}

# Function to get client information for the active workspace
get_workspace_clients() {
  local workspace_id="$1"
  hyprctl clients -j | jq -r --argjson ws_id "$workspace_id" '.[] | select(.workspace.id == $ws_id and .floating == false)'
}

# Function to apply the 80/20 layout
apply_layout() {
  if [[ ! -f "$LAYOUT_STATE_FILE" ]]; then
    # Feature is disabled, do nothing
    return
  fi

  local ws_id=$(get_active_workspace)
  local clients_json=$(get_workspace_clients "$ws_id")
  local num_clients=$(echo "$clients_json" | jq -r 'length')

  if [[ "$num_clients" -ne 2 ]]; then
    # Only apply if exactly two non-floating windows are present
    return
  fi

  local focused_window_address=$(hyprctl activewindow -j | jq -r '.address')
  local unfocused_window_address=""
  local client_addresses=()

  while IFS= read -r line; do
    local addr=$(echo "$line" | jq -r '.address')
    if [[ "$addr" == "$focused_window_address" ]]; then
      WINDOW_DATA["focused_monitor"]=$(echo "$line" | jq -r '.monitor')
    else
      unfocused_window_address="$addr"
    fi
    client_addresses+=("$addr")
  done <<< "$clients_json"

  # Get monitor dimensions (assuming both windows are on the same monitor)
  local monitor_width=$(hyprctl monitors -j | jq -r --argjson mon_id "${WINDOW_DATA["focused_monitor"]}" '.[] | select(.id == $mon_id) | .width')
  local monitor_height=$(hyprctl monitors -j | jq -r --argjson mon_id "${WINDOW_DATA["focused_monitor"]}" '.[] | select(.id == $mon_id) | .height')

  # Calculate desired sizes
  local eighty_percent_width=$(( monitor_width * 8 / 10 ))
  local twenty_percent_width=$(( monitor_width * 2 / 10 ))

  # Determine which window is master and which is stack in Hyprland's current layout
  # This is a bit tricky as Hyprland might not expose this directly without complex parsing.
  # For simplicity, we assume one is at 0,0 and the other next to it for the split.
  # We will enforce the left 80% / right 20% split based on focus.

  # Window rule for focused window to be 80% and at x=0
  local rule_focused="windowrule float,address:$focused_window_address; windowrule size $eighty_percent_width $monitor_height,address:$focused_window_address; windowrule move 0 0,address:$focused_window_address"
  # Window rule for unfocused window to be 20% and at x=80%_width
  local rule_unfocused="windowrule float,address:$unfocused_window_address; windowrule size $twenty_percent_width $monitor_height,address:$unfocused_window_address; windowrule move $eighty_percent_width 0,address:$unfocused_window_address"

  hyprctl --batch "$rule_focused;$rule_unfocused"
}

start_daemon() {
  if [[ -f "$DAEMON_PID_FILE" ]] && kill -0 "$(cat "$DAEMON_PID_FILE")" 2>/dev/null; then
    echo "Daemon already running with PID $(cat "$DAEMON_PID_FILE")"
    exit 0
  fi

  # Remove old PID file if process not running
  if [[ -f "$DAEMON_PID_FILE" ]]; then
    rm "$DAEMON_PID_FILE"
  fi

  # Start daemon in background
  (
    echo "$" > "$DAEMON_PID_FILE"
    socat - UNIX-CONNECT:"$HYPR_EVENT_SOCK" | while IFS= read -r line; do
      # echo "Event received: $line" >> /tmp/hypr_daemon_debug.log # For debugging
      if [[ "$line" == "activewindow>*" || "$line" == "workspace>*" || "$line" == "createwindow>*" || "$line" == "closewindow>*" ]]; then
        # Delay to allow Hyprland to settle after event
        sleep 0.1
        apply_layout
      fi
    done
  ) &
  echo "Daemon started with PID $!"
}

stop_daemon() {
  if [[ -f "$DAEMON_PID_FILE" ]]; then
    kill "$(cat "$DAEMON_PID_FILE")" 2>/dev/null
    rm "$DAEMON_PID_FILE"
    echo "Daemon stopped."
  else
    echo "Daemon not running."
  fi
}

toggle_layout_feature() {
  if [[ -f "$LAYOUT_STATE_FILE" ]]; then
    rm "$LAYOUT_STATE_FILE"
    notify-send "Hyprland Layout" "80/20 Layout DISABLED"
  else
    touch "$LAYOUT_STATE_FILE"
    notify-send "Hyprland Layout" "80/20 Layout ENABLED"
    # Re-apply layout immediately if daemon is running and feature enabled
    if [[ -f "$DAEMON_PID_FILE" ]] && kill -0 "$(cat "$DAEMON_PID_FILE")" 2>/dev/null; then
      apply_layout
    fi
  fi
}

# Main execution logic
case "$1" in
  start)
    start_daemon
    ;;
  stop)
    stop_daemon
    ;;
  toggle)
    toggle_layout_feature
    ;;
  *)
    echo "Usage: $0 {start|stop|toggle}"
    exit 1
    ;;
esac