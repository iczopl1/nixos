z() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      local selected_dir
      selected_dir="$(find . -type d -print 2>/dev/null | fzf --prompt='sub-dir> ')"
      if [[ -n "$selected_dir" ]]; then
        cd "$selected_dir" || return
        command -v zoxide >/dev/null 2>&1 && zoxide add "$PWD" >/dev/null 2>&1 || true
        return
      else
        return # No directory selected, so don't change directory.
      fi
    else
      cd "${HOME}" || return
      return
    fi
  fi

  local target
  # Attempt 1: Exact match for a subdirectory name
  target="$(find . -mindepth 1 -maxdepth 1 -type d -name "$query" -print -quit 2>/dev/null)"
  if [[ -n "$target" ]]; then
    cd "$target" || return
    command -v zoxide >/dev/null 2>&1 && zoxide add "$PWD" >/dev/null 2>&1 || true
    return
  fi

  # Attempt 2: Match query followed by 'files' (e.g., 'dot' -> 'dotfiles')
  target="$(find . -mindepth 1 -maxdepth 1 -type d -name "${query}files" -print -quit 2>/dev/null)"
  if [[ -n "$target" ]]; then
    cd "$target" || return
    command -v zoxide >/dev/null 2>&1 && zoxide add "$PWD" >/dev/null 2>&1 || true
    return
  fi

  # Attempt 3: Match query followed by 's' (e.g., 'doc' -> 'docs')
  target="$(find . -mindepth 1 -maxdepth 1 -type d -name "${query}s" -print -quit 2>/dev/null)"
  if [[ -n "$target" ]]; then
    cd "$target" || return
    command -v zoxide >/dev/null 2>&1 && zoxide add "$PWD" >/dev/null 2>&1 || true
    return
  fi
  
  # Attempt 4: Match query as a prefix (existing behavior, but now prioritized lower)
  target="$(find . -mindepth 1 -maxdepth 1 -type d -name "${query}*" -print 2>/dev/null | sort | head -n 1)"
  if [[ -n "$target" ]]; then
    cd "$target" || return
    command -v zoxide >/dev/null 2>&1 && zoxide add "$PWD" >/dev/null 2>&1 || true
    return
  fi

  target="$(zoxide query -- "$@" 2>/dev/null)" && cd "$target"
}
