#!/usr/bin/env bash
# First process in a daemon alacritty window (see spawn-alacritty.sh).
# `alacritty msg create-window -o ...` ignores -o in alacritty 0.16, so the
# window applies its own palette over IPC, then runs the command or shell.
# Usage: alacritty-init.sh [KEY=VALUE ...] -- [COMMAND ...]
opts=()
while (( $# )) && [[ $1 != -- ]]; do opts+=("$1"); shift; done
(( $# )) && shift

if (( ${#opts[@]} )) && [[ -n ${ALACRITTY_WINDOW_ID:-} ]]; then
  alacritty msg config -w "$ALACRITTY_WINDOW_ID" "${opts[@]}" >/dev/null 2>&1
fi

(( $# )) && exec "$@"
exec "${SHELL:-bash}"
