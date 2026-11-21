#!/usr/bin/env bash
# One entry point for power-fx (the cursor effects).
#   power-fx.sh start     stop any old copy, then start a fresh one
#   power-fx.sh stop      clean up old standalone copies (the bar-hosted one keeps running)
#   power-fx.sh restart   same as start
#   power-fx.sh status    show if it is running
dir=$(cd "$(dirname "$0")" && pwd)
pidfile=${XDG_RUNTIME_DIR:-/tmp}/power-fx.pid

stop() {
    # power-fx now lives inside the bar (bar/Fx.qml). It cannot be stopped alone:
    # use  power-fx.sh off pet  etc., or restart the bar. This only cleans up old standalone copies.
    pkill -f "^quickshell -p $dir/shell.qml" 2>/dev/null
    rm -f "$pidfile"
    "$dir/cursor-hide.sh" off   # always give the real cursor back
    return 0
}

build() {
    # Rebuild ptrwatch when the source is newer than the program.
    if [ ! -x "$dir/ptrwatch" ] || [ "$dir/ptrwatch.cpp" -nt "$dir/ptrwatch" ]; then
        cxx=$(command -v g++ || ls -d /nix/store/*-gcc-wrapper-*/bin/g++ 2>/dev/null | head -1)
        if [ -z "$cxx" ]; then
            echo "no g++ found; build ptrwatch.cpp yourself: g++ -O2 -std=c++17 -o ptrwatch ptrwatch.cpp" >&2
            return 1
        fi
        "$cxx" -O2 -std=c++17 -Wall -Wextra -o "$dir/ptrwatch" "$dir/ptrwatch.cpp" || return 1
    fi
}

start() {
    stop
    build || return 1
    echo "built. power-fx runs inside the bar: restart the bar with ~/.config/hypr/qs-launcher.sh (or SUPER+F11)"
}

case "${1:-status}" in
    start|restart) start ;;
    stop) stop; echo stopped ;;
    status)
        if timeout 3 qs -c bar ipc show 2>/dev/null | grep -q 'target fx'; then echo "running (inside the bar)"; else echo "not running"; fi ;;
    list)   # every effect with ON / off, taken from effects.conf
        sed -nE 's/^#?[[:space:]]*([a-z]+)[[:space:]]+#[[:space:]]*(.*)$/\0/p' "$dir/effects.conf" | while IFS= read -r l; do
            case "$l" in '#'*) printf 'off  %s\n' "${l#\#}" ;; *) printf 'ON   %s\n' "$l" ;; esac
        done ;;
    toggle|on|off)   # toggle NAME | on NAME | off NAME  (or just edit effects.conf and add/remove the #)
        name=$2
        if ! grep -qE "^#?[[:space:]]*$name[[:space:]]" "$dir/effects.conf" 2>/dev/null || [ -z "$name" ]; then
            echo "unknown effect; see: power-fx.sh list"; exit 1
        fi
        grep -qE "^$name[[:space:]]" "$dir/effects.conf" && cur=on || cur=off
        case "$1" in on) new=on ;; off) new=off ;; *) [ "$cur" = on ] && new=off || new=on ;; esac
        if [ "$new" = off ]; then sed -i -E "s/^$name([[:space:]])/#$name\1/" "$dir/effects.conf"
        else sed -i -E "s/^#[[:space:]]*$name([[:space:]])/$name\1/" "$dir/effects.conf"; fi
        echo "$name $new" ;;
    boost)  # run the effects for N minutes even on battery (default 10); boost 0 = stop now
        timeout 5 qs -c bar ipc call fx boost "${2:-10}" ;;
    peak)   # freeze one effect (1..5) for 3 s, for screenshots
        timeout 5 qs -c bar ipc call fx peak "${2:-1}" ;;
    play)   # preview a swap effect on the focused tile: play 1..5, or play 0 = all five in turn
        timeout 5 qs -c bar ipc call fx play "${2:-0}" ;;
    wow) timeout 5 qs -c bar ipc call fx wow "${2:-sweep}" ;;
    urgent) timeout 5 qs -c bar ipc call fx urgent "${2:-8}" ;;
    move)   # effects used for real tile moves: move 2 = landing flash on the focused tile; move 0 = off
        timeout 5 qs -c bar ipc call fx move "${2:-0}" ;;
    pet)    # preview the pet: pet type | notify | plug | flee | hide | poke | sleep | dare | lap | peek | startle | trick | screen | ripple | burst
        timeout 5 qs -c bar ipc call fx pet "${2:-type}" ;;
    *) echo "usage: $0 {start|stop|restart|status|boost [min]|play [0-5]|move [digits, e.g. 2]|pet [type|notify|plug|flee|hide|poke|sleep|dare|lap|peek|startle|trick|screen|ripple|burst|tag|merge|panic]}"; exit 1 ;;
esac
