#!/bin/sh
# Lock screen. It lives inside the bar (~/.config/quickshell/bar/Lock.qml),
# so there is no separate lock process.
#   qs-lock.sh            lock now (starts the bar if it isn't running)
#   qs-lock.sh --daemon   no-op, kept so old exec_once lines still work
#   qs-lock.sh --test N   lock, unlock by itself after N seconds
[ "$1" = --daemon ] && exit 0

secs=0; [ "$1" = --test ] && secs="${2:-30}"
if [ "$secs" -gt 0 ]; then call="test $secs"; else call=lock; fi
timeout 2 qs -c bar ipc call lock $call >/dev/null 2>&1 && exit 0
# bar not running: start it, locked straight away
QS_LOCK_NOW="$secs" QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 setsid -f qs -n -c bar >/dev/null 2>&1
