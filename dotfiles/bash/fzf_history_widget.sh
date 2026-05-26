#!/usr/bin/env bash

# FZF history search for Ctrl+R
function __fzf_history_search_widget {
  local selected
  selected="$(history | fzf --no-sort --tac --reverse --height "${FZF_TMUX_HEIGHT:-40%}" --layout=reverse --border --prompt="history> ")"
  READLINE_LINE="$selected"
  READLINE_POINT="${#READLINE_LINE}"
}
bind -x '"\C-r": __fzf_history_search_widget'
