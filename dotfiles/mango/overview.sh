#!/usr/bin/env bash
# overview.sh toggle|close  -- overview + keymode "overview" (Enter/Esc = leave on the focused window)
mon=${TOUCH_MON:-eDP-1}
j=$(mmsg get monitor "$mon" 2>/dev/null)
n=$(grep -o '"tag_num":[0-9]*' <<<"$j" | grep -o '[0-9]*$')
a=$(grep -o '"is_active":true' <<<"$j" | wc -l)
in=0; [[ -n $n && $n -ge 2 && $a -ge $n ]] && in=1
if (( in )); then
  mmsg dispatch toggleoverview; mmsg dispatch setkeymode,default
elif [[ ${1:-toggle} == toggle ]]; then
  mmsg dispatch toggleoverview; mmsg dispatch setkeymode,overview
else
  mmsg dispatch setkeymode,default
fi
