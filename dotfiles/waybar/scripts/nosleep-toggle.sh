#!/usr/bin/env bash
# Click handler for the nosleep dot: same as the `nosleep` alias in ~/.bashrc,
# or cancels it if already active.
why="skip next lid close"
if systemd-inhibit --list --no-legend 2>/dev/null | grep -q "$why"; then
  pkill -f "systemd-inhibit --what=handle-lid-switch --why=$why"
else
  setsid -f systemd-inhibit --what=handle-lid-switch --why="$why" sh -c 'f=/proc/acpi/button/lid/LID0/state; until grep -q closed $f; do sleep 1; done; until grep -q open $f; do sleep 1; done' >/dev/null 2>&1
fi
