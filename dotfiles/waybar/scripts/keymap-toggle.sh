#!/usr/bin/env bash
# Click handler for the keymap dot: same toggle as SUPER+TAB.
if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
  [ "$(mmsg get keymode | jq -r .keymode)" = clean ] && m=default || m=clean
  exec mmsg dispatch setkeymode,$m
fi
if [ "$(hyprctl submap 2>/dev/null)" = clean ]; then
  hyprctl dispatch submap reset
else
  hyprctl dispatch submap clean
fi
