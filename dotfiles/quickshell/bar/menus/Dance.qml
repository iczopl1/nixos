import QtQuick
import Quickshell
import ".."

// Mouse dance picker: the pointer flies a pattern until Esc. The motion lives in Fx.qml
// (`mousedance` in power-fx effects.conf, AC only); this menu only picks the pattern.
MenuBox {
    id: root

    signal close
    signal dance(string pattern)

    function open() { reset(); }

    items: [
        { key: "buttons",   text: "Buttons     jump between every button on screen, one random order, looped" },
        { key: "tiles",     text: "Tiles       jump between the windows on this screen, one random order, looped" },
        { key: "infinity",  text: "Infinity    figure eight, fast through the middle" },
        { key: "pentagon",  text: "Pentagon    straight edges, slowly turning" },
        { key: "mimic",     text: "Mimic       your own doodling, re-invented: circles fitted to your recording" },
        { key: "tour",      text: "Tour        every pattern in turn, morphing into the next" },
        { key: "lissajous", text: "Lissajous   3:2 knot that slowly twists" },
        { key: "rose",      text: "Rose        five-petal rhodonea, petals overlap" },
        { key: "spiro",     text: "Spirograph  looping hypotrochoid" },
        { key: "star",      text: "Star        five sharp cusps, flicks at each tip" },
        { key: "butterfly", text: "Butterfly   Fay's butterfly curve" },
        { key: "heart",     text: "Heart       beating heart" },
        { key: "galaxy",    text: "Galaxy      spiral that breathes out and in" },
        { key: "orbit",     text: "Orbit       moon around a planet around the centre" },
        { key: "lorenz",    text: "Lorenz      chaotic butterfly attractor, never repeats" },
        { key: "dvd",       text: "DVD         bounces off the screen edges" }
    ]
    prompt: "DANCE"; placeholder: "Pick a pattern (Esc stops it)"

    onPicked: item => {
        dance(item.key);
        close();
    }
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F2262A33"; panel: Theme.isLight ? "#80D8D0BF" : "#80485468"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2A5B8D8"
    borderColor: Theme.isLight ? "#9A937F" : "#8FA3C4"; borderSoft: Theme.isLight ? "#B9B2A3" : "#5E6E8A"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#8E99AD"; accent: Theme.isLight ? "#1A5FB4" : "#9DB4DA"; selText: "#161B26"

    width: 900
    columns: 1; lines: 16; spacing: 10
    elemRadius: 20; padV: 10; padH: 14
}
