#!/usr/bin/env bash
# Network state for custom/network: off / no internet / no DNS / online.
#   off          no default route (wifi off or not connected)
#   no-internet  linked, but 8.8.8.8 does not answer
#   no-dns       8.8.8.8 answers, wp.pl does not (resolve + ping)
#   online       wp.pl answers
# Long-running; prints a JSON line only when the state changes. Rechecks on
# NetworkManager events (nmcli monitor) and otherwise on a slow timer, so the
# steady state is one short ping pair every ONLINE_EVERY seconds.

set -u

IP_TARGET=8.8.8.8
DNS_TARGET=wp.pl
ONLINE_EVERY=30   # seconds between checks while everything works
DEGRADED_EVERY=5  # while linked but something fails
OFF_EVERY=60      # while off; NM events wake us sooner

# Font Awesome solid glyphs
ICON_OFF=$''          # ban
ICON_NO_INTERNET=$''  # triangle-exclamation
ICON_NO_DNS=$''       # question
ICON_WIFI=$''         # wifi
ICON_ETHERNET=$''     # ethernet

# Same lifecycle handling as keymap-state.sh: take nmcli monitor down with us,
# and exit once waybar is gone even if it did not signal.
trap 'trap - TERM INT HUP PIPE EXIT; kill 0 2>/dev/null' TERM INT HUP PIPE EXIT
read -r _ _ _ parent _ < /proc/$$/stat
orphaned() {
  local ppid
  read -r _ _ _ ppid _ < /proc/$$/stat
  [ "$ppid" != "$parent" ]
}

# pango + JSON escaping for the SSID
escape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  printf '%s' "$s"
}

wifi_dev=
for d in /sys/class/net/*/wireless; do
  [ -d "$d" ] && { wifi_dev=${d%/wireless}; wifi_dev=${wifi_dev##*/}; break; }
done

# default route straight from /proc: no fork per check
has_default_route() {
  local iface dest _rest
  while read -r iface dest _rest; do
    [ "$dest" = 00000000 ] && return 0
  done < /proc/net/route
  return 1
}

ssid=
refresh_ssid() {
  ssid=
  [ -n "$wifi_dev" ] || return
  ssid=$(nmcli -t -g GENERAL.CONNECTION device show "$wifi_dev" 2>/dev/null)
}

last=
interval=$OFF_EVERY
check() {
  local state icon text tooltip radio=0 kind=ethernet link_icon=$ICON_ETHERNET
  if [ -n "$wifi_dev" ] && [ "$(< "/sys/class/net/$wifi_dev/operstate")" = up ]; then
    kind=wifi link_icon=$ICON_WIFI
  fi

  if ! has_default_route; then
    state=off icon=$ICON_OFF interval=$OFF_EVERY
    if [ "$(nmcli radio wifi 2>/dev/null)" = disabled ]; then
      text="Off" tooltip="Wi-Fi off" radio=1
    else
      text="Disconnected" tooltip="Not connected"
    fi
  else
    local name
    if [ "$kind" = wifi ]; then name=$(escape "${ssid:-Wi-Fi}"); else name=Wired; fi
    if ! ping -c1 -W2 -n -q "$IP_TARGET" >/dev/null 2>&1; then
      state=no-internet icon=$ICON_NO_INTERNET interval=$DEGRADED_EVERY
      tooltip="$name: no internet ($IP_TARGET unreachable)"
    elif ! ping -c1 -W2 -q "$DNS_TARGET" >/dev/null 2>&1; then
      state=no-dns icon=$ICON_NO_DNS interval=$DEGRADED_EVERY
      tooltip="$name: no DNS ($IP_TARGET ok, $DNS_TARGET unreachable)"
    else
      state=online icon=$link_icon interval=$ONLINE_EVERY
      tooltip="$name: online"
    fi
    text=$name
  fi

  local line cls="\"$state\""
  [ "$radio" = 1 ] && cls='["off","no-radio"]'   # wifi radio disabled: the bar shows a cross
  printf -v line '{"text":"%s  %s","class":%s,"alt":"%s","tooltip":"%s"}' \
    "$icon" "$text" "$cls" "$state" "$tooltip"
  if [ "$line" != "$last" ]; then
    printf '%s\n' "$line"
    last=$line
  fi
}

start_monitor() {
  coproc NM { exec nmcli monitor 2>/dev/null; }
}

# --once: print the state once and exit. The quickshell bar runs it on NetWatch
# events and on a timer, so no long-lived nmcli monitor is left behind.
if [ "${1:-}" = --once ]; then
  refresh_ssid
  check
  exit 0
fi

refresh_ssid
start_monitor
check

while :; do
  orphaned && exit 0
  if [ -n "${NM_PID:-}" ] && read -r -t "$interval" -u "${NM[0]}" _; then
    # an event: let the burst settle (connect = several lines), then recheck
    while read -r -t 1 -u "${NM[0]}" _; do :; done
    refresh_ssid
  elif [ $? -le 128 ]; then
    # nmcli monitor gone (NM restarting?): plain timer, retry it later
    sleep "$interval" & wait $!
    start_monitor 2>/dev/null
    refresh_ssid
  fi
  check
done
