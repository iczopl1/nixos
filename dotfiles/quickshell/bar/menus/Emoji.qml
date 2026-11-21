import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// SUPER+; emoji picker, a port of ~/.config/hypr/rofi-emoji-picker.sh with rofi-emoji.rosi.
// The list is read once at startup (`rofi-emoji-picker.sh --print`), so opening runs nothing.
MenuBox {
    id: root

    signal close

    function open() { reset(); }

    Process {
        running: true
        command: [Quickshell.env("HOME") + "/.config/hypr/rofi-emoji-picker.sh", "--print"]
        stdout: StdioCollector {
            onStreamFinished: root.items = text.split("\n").filter(l => l.includes("\t")).map(l => {
                const t = l.indexOf("\t");
                return { text: l.slice(0, t), meta: l.slice(t + 1) };
            })
        }
    }

    // copy, then paste into the window that gets focus back once we close
    Process {
        id: paste
        property string emoji
        command: ["sh", "-c", `printf %s "$1" | wl-copy --type text/plain
if command -v ydotool >/dev/null 2>&1; then
  sleep 0.08
  [ -S /run/ydotoold/socket ] && export YDOTOOL_SOCKET="\${YDOTOOL_SOCKET:-/run/ydotoold/socket}"
  ydotool key 29:1 47:1 47:0 29:0 || true
elif command -v wtype >/dev/null 2>&1; then
  sleep 0.05
  wtype -- "$1" || true
fi
notify-send -a rofi Emoji "Copied and pasted $1"`, "_", emoji]
    }

    onPicked: item => {
        close();
        paste.emoji = item.text;
        paste.running = true;
    }
    onCancelled: close()

    bg: Theme.isLight ? "#F2F6F1E7" : "#F22E3440"; panel: Theme.isLight ? "#80D8D0BF" : "#804C566A"; panelStrong: Theme.isLight ? "#F2CFD8E6" : "#F2A5C4AE"
    borderColor: Theme.isLight ? "#9A937F" : "#8FA89A"; borderSoft: Theme.isLight ? "#B9B2A3" : "#738E7E"
    textColor: Theme.isLight ? "#2A2A2E" : "#ECEFF4"; textFaint: Theme.isLight ? "#6B6A70" : "#8DA193"; accent: Theme.isLight ? "#1A5FB4" : "#9AB9A5"; selText: "#17261d"
    prompt: "EMOJI"; placeholder: "Search emoji"
    fontFamily: "Noto Color Emoji"
    fontPt: 18
    itemPt: 22
    centerText: true

    width: 760
    columns: 10; lines: 6; spacing: 10
    elemRadius: 20; padV: 8; padH: 8
}
