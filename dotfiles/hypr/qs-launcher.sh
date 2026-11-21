#!/bin/sh
# Toggle a Quickshell menu (~/.config/quickshell/bar/Menus.qml). The menus live in
# the bar process and are kept ready, so opening skips Quickshell's startup.
#   qs-launcher.sh          toggle the SUPER-tap app launcher
#   qs-launcher.sh <name>   toggle that menu: apps clip emoji bluetooth audio keybinds wallpaper
# Binds call socat on the socket directly; this script is the fallback that starts the bar.
dir="${XDG_RUNTIME_DIR:-/tmp}"
name="${1:-launcher}"
if [ "$name" = launcher ]; then
  sock="$dir/qs-launcher-${WAYLAND_DISPLAY:-wayland-0}.sock"
else
  sock="$dir/qs-menu-$name-${WAYLAND_DISPLAY:-wayland-0}.sock"
fi

# fast path: the menu's own socket, ~7ms vs ~55ms for qs ipc
socat -u /dev/null "UNIX-CONNECT:$sock" 2>/dev/null && exit 0
# bar not running: start it, then open the menu once it answers.
#
# Why the LD_LIBRARY_PATH cleanup below (added 2026-11-04):
# The `claude` command (Claude Code, nix wrapper) exports LD_LIBRARY_PATH with
# <alsa-lib-1.2.16.1>/lib. That alsa-lib is built for glibc 2.43; the system has 2.40.
# If the bar is started from a Claude shell, it inherits that path, and every app
# started from the launcher then dies with "GLIBC_2.43 not found" (seen with
# ferdium-wayland; it worked fine from a terminal). A clean session only has
# /etc/sane-libs. So drop any alsa-lib entry here and keep the rest.
# To check a running bar: tr '\0' '\n' < /proc/<bar pid>/environ | grep LD_LIBRARY_PATH
LD_LIBRARY_PATH=$(printf '%s' "${LD_LIBRARY_PATH:-}" | tr ':' '\n' | grep -v -e '-alsa-lib-' -e '^$' | paste -sd: -)
if [ -n "$LD_LIBRARY_PATH" ]; then export LD_LIBRARY_PATH; else unset LD_LIBRARY_PATH; fi
setsid -f qs -n -c bar >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.2
  timeout 2 qs -c bar ipc call menus toggle "$name" >/dev/null 2>&1 && exit 0
done
