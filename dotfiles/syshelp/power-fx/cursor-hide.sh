#!/usr/bin/env bash
# Hide / show the real mouse cursor by switching mango's cursor_theme.
#   cursor-hide.sh on    -> cursor_theme=invisible (theme in ~/.local/share/icons/invisible)
#   cursor-hide.sh off   -> back to the theme that was set before
# It rewrites ONLY ~/.config/mango/mango-cursor.conf (sourced by config.conf), never config.conf,
# so a failed write can never touch the keybinds. Then `mmsg dispatch reload_config`.
# Emergency restore if the cursor stays hidden:  ~/syshelp/power-fx/cursor-hide.sh off
cfg=$HOME/.config/mango/mango-cursor.conf
state=${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/power-fx.cursor-theme
hidden=invisible

exec 9>"$state.lock"; flock 9      # one run at a time

cur=$(sed -n 's/^cursor_theme=\(.*\)$/\1/p' "$cfg" | head -1)

set_theme() {
    # temp file in the same folder, then mv: the file is never empty or half written
    tmp=$(mktemp "$cfg.XXXXXX") || return 1
    sed "s/^cursor_theme=.*/cursor_theme=$1/" "$cfg" > "$tmp" && grep -q "^cursor_theme=$1\$" "$tmp" \
        && grep -q '^cursor_size=' "$tmp" && mv -f "$tmp" "$cfg" || { rm -f "$tmp"; return 1; }
}

case "${1:-}" in
    on)
        [ "$cur" = "$hidden" ] && exit 0
        printf '%s\n' "$cur" > "$state"
        set_theme "$hidden" || exit 1
        ;;
    off)
        [ "$cur" != "$hidden" ] && exit 0
        orig=$(cat "$state" 2>/dev/null)
        [[ $orig =~ ^[A-Za-z0-9._-]+$ ]] || orig=Adwaita   # only plain theme names go into sed
        set_theme "$orig" || exit 1
        rm -f "$state"
        ;;
    *)
        echo "usage: $0 {on|off}" >&2
        exit 1
        ;;
esac
timeout 5 mmsg dispatch reload_config >/dev/null 2>&1
