#!/usr/bin/env bash

# This script manages a dynamic 80/20 window layout for two windows on a workspace.
# Focused window takes 80%, unfocused takes 20%. Toggles this behavior.

LAYOUT_STATE_FILE="/tmp/hypr_two_window_layout_enabled"
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
  local ws_id=$(get_active_workspace)
  local clients_json=$(get_workspace_clients "$ws_id")
  local num_clients=$(echo "$clients_json" | jq -r 'length')

  if [[ "$num_clients" -ne 2 ]]; then
    # Only apply if exactly two non-floating windows are present
    exit 0
  fi

  local focused_window_address=$(hyprctl activewindow -j | jq -r '.address')
  local unfocused_window_address=""
  local client_addresses=()

  while IFS= read -r line; do
    local addr=$(echo "$line" | jq -r '.address')
    if [[ "$addr" == "$focused_window_address" ]]; then
      WINDOW_DATA["focused_pid"]=$(echo "$line" | jq -r '.pid')
      WINDOW_DATA["focused_x"]=$(echo "$line" | jq -r '.at[0]')
      WINDOW_DATA["focused_y"]=$(echo "$line" | jq -r '.at[1]')
      WINDOW_DATA["focused_w"]=$(echo "$line" | jq -r '.size[0]')
      WINDOW_DATA["focused_h"]=$(echo "$line" | jq -r '.size[1]')
      WINDOW_DATA["focused_monitor"]=$(echo "$line" | jq -r '.monitor')
    else
      unfocused_window_address="$addr"
      WINDOW_DATA["unfocused_pid"]=$(echo "$line" | jq -r '.pid')
      WINDOW_DATA["unfocused_x"]=$(echo "$line" | jq -r '.at[0]')
      WINDOW_DATA["unfocused_y"]=$(echo "$line" | jq -r '.at[1]')
      WINDOW_DATA["unfocused_w"]=$(echo "$line" | jq -r '.size[0]')
      WINDOW_DATA["unfocused_h"]=$(echo "$line" | jq -r '.size[1]')
      WINDOW_DATA["unfocused_monitor"]=$(echo "$line" | jq -r '.monitor')
    fi
    client_addresses+=("$addr")
  done <<< "$clients_json"

  # Get monitor dimensions
  local monitor_name=$(hyprctl monitors -j | jq -r --argjson mon_id "${WINDOW_DATA["focused_monitor"]}" '.[] | select(.id == $mon_id) | .name')
  local monitor_width=$(hyprctl monitors -j | jq -r --argjson mon_id "${WINDOW_DATA["focused_monitor"]}" '.[] | select(.id == $mon_id) | .width')
  local monitor_height=$(hyprctl monitors -j | jq -r --argjson mon_id "${WINDOW_DATA["focused_monitor"]}" '.[] | select(.id == $mon_id) | .height')

  # Calculate desired sizes
  local eighty_percent_width=$(( monitor_width * 8 / 10 ))
  local twenty_percent_width=$(( monitor_width * 2 / 10 ))

  # Apply sizes (focused 80%, unfocused 20%)
  # This logic is simplified: always try to make focused 80% left, unfocused 20% right
  # It will enforce a specific ordering and might override Hyprland's tiling.
  # For true dynamic swapping, the 'movewindow' and 'resizewindow' commands need to be
  # carefully coordinated to reflect the current window positions and desired swap.
  # This is a basic example to illustrate the concept.

  # Get current window layout (addresses as seen by Hyprland's internal tiler)
  # This is crucial for correctly applying the split without fighting the tiler.
  # We assume a master-stack layout for two windows.
  local master_client=$(hyprctl workspaces -j | jq -r --argjson ws_id "$ws_id" '.[] | select(.id == $ws_id) | .windows[0].address')
  local stack_client=$(hyprctl workspaces -j | jq -r --argjson ws_id "$ws_id" '.[] | select(.id == $ws_id) | .windows[1].address')

  if [[ -z "$master_client" || -z "$stack_client" ]]; then
      # Something went wrong, or not a simple master-stack layout
      exit 0
  fi

  # Apply window rules for fixed sizing on a workspace.
  # This is a workaround as Hyprland's dispatch doesn't easily allow relative sizing based on focus.
  # We apply rules for the windows if they match.
  if [[ "$focused_window_address" == "$master_client" ]]; then
      # Focused is master, make master 80%, stack 20%
      hyprctl --batch "windowrule float,address:$master_client;\
                       windowrule size $eighty_percent_width $monitor_height,address:$master_client;\
                       windowrule move 0 0,address:$master_client;\
                       windowrule float,address:$stack_client;\
                       windowrule size $twenty_percent_width $monitor_height,address:$stack_client;\
                       windowrule move $((eighty_percent_width)) 0,address:$stack_client"
  else # Focused is stack, make stack 80%, master 20%
      hyprctl --batch "windowrule float,address:$stack_client;\
                       windowrule size $eighty_percent_width $monitor_height,address:$stack_client;\
                       windowrule move 0 0,address:$stack_client;\
                       windowrule float,address:$master_client;\
                       windowrule size $twenty_percent_width $monitor_height,address:$master_client;\
                       windowrule move $((eighty_percent_width)) 0,address:$master_client"
  fi
}

toggle_state() {
  if [[ -f "$LAYOUT_STATE_FILE" ]]; then
    rm "$LAYOUT_STATE_FILE"
    notify-send "Hyprland Layout" "80/20 Layout DISABLED (Restart windows for full effect)"
    # Clear rules when disabled
    # This is tricky as we need to know original sizes/positions.
    # For now, simply removing the state file is enough.
  else
    touch "$LAYOUT_STATE_FILE"
    notify-send "Hyprland Layout" "80/20 Layout ENABLED"
    apply_layout # Apply layout immediately when enabled
  fi
}

# Main execution
if [[ "$1" == "toggle" ]]; then
  toggle_state
elif [[ -f "$LAYOUT_STATE_FILE" ]]; then
  # This branch will be executed if the script is run without "toggle"
  # and the feature is enabled. This can be used for event-driven updates.
  apply_layout
fi