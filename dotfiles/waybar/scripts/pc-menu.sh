#!/usr/bin/env bash
# fzf menu for a desktop host, run inside a terminal by its bar chip (like robot-menu.sh).
# Usage: pc-menu.sh <moonlight-host> <ssh-host>   e.g. pc-menu.sh my-pc my-pc-ssh
set -u

name="$1" host="$2"

choice=$(printf '%s\n' \
  "shell        ssh $host" \
  "moonlight    remote desktop (Desktop)" |
  fzf --prompt="$name ($host) > " --height=100% --layout=reverse --no-multi --cycle) || exit 0

case "$choice" in
  shell*) exec ssh "$host" ;;
  # flags of the rd alias in ~/.bashrc, but double the bitrate (5000); detached so this terminal can close
  moonlight*)
    setsid -f moonlight stream --1080 --fps 60 --bitrate 5000 --video-codec AV1 \
      --packet-size 1024 --display-mode fullscreen --game-optimization \
      --frame-pacing --no-vsync --no-audio-on-host --quit-after "$name" Desktop >/dev/null 2>&1
    exit 0 ;;
esac
