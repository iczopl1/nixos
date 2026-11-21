//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// Waybar port. Start with: qs -c bar
// Always shown, on every tag/workspace (with or without windows open) and on every
// monitor (Variants below, model: Quickshell.screens). `qs -c bar ipc call bar toggle`
// (the F11 bind) is still a manual show/hide, independent of tag contents.
ShellRoot {
    id: root

    property bool shown: true

    IpcHandler {
        target: "bar"

        function toggle(): void {
            root.shown = !root.shown;
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            shown: root.shown
        }
    }

    // rofi menus + SUPER-tap launcher (was its own `qs -c launcher` process)
    Menus {
        onDance: pattern => fx.dance(pattern)
    }

    // SUPER+D hint overlay (hintd does the accessibility reading and the click)
    Hints {}

    // SUPER+H shortcuts cheatsheet, WPM-driven window border/glow, particle themes
    // (SUPER+F6) – moved here from the old standalone root shell.qml during the
    // 2026-11-18 dotfiles merge, so they live in this one qs process like everything
    // else instead of a second quickshell nothing starts anymore.
    Shortcuts {}
    Component.onCompleted: {
        var _p = Particles.active;
        var _w = WpmBorder.wpm;
        var _g = TypingGlow.active; // TypingGlow is `pragma Singleton` – `TypingGlow {}` is not
                                     // valid QML (not creatable); force it the same way as Particles.
        // T2.40: thermal safety throttle (85C -> max_perf_pct 50%, hysteresis to 70C).
        // Also `pragma Singleton` – force instantiation the same way, not gated by AC power.
        var _t = ThermalThrottle.active;
    }

    // SUPER+F3 screen drawing (was the separate `wayscriber` process)
    Draw {}

    // lock screen (was its own `qs -c lock` process)
    Lock {}

    // were hypr/audio-route-watch.sh and mango/autorotate.sh (bash + pw-dump + jq, sh + sh)
    AudioRouter {}
    Rotate {}

    // notification daemon (was the separate `mako` process)
    Notifications { id: notifs }

    // cursor + desktop effects, AC power only (was the separate `power-fx` process)
    Fx { id: fx }

    Connections {
        target: notifs
        function onShown() { fx.notified(); }
    }
}
