import QtQuick
import Quickshell

// waybar "clock": click swaps to format-alt, the tooltip is a month calendar
// with waybar's colors; scrolling moves the calendar a month.
Seg {
    id: root

    property bool alt: false
    property int shift: 0

    SystemClock {
        id: clock
        precision: root.alt ? SystemClock.Seconds : SystemClock.Minutes
    }

    function pad(n) {
        return String(n).padStart(2, " ");
    }

    function calendar() {
        const now = clock.date;
        const first = new Date(now.getFullYear(), now.getMonth() + shift, 1);
        const y = first.getFullYear(), m = first.getMonth();
        const days = new Date(y, m + 1, 0).getDate();
        const isThisMonth = y === now.getFullYear() && m === now.getMonth();
        const title = Qt.formatDate(first, "MMMM yyyy");
        const span = (c, t) => "<span style='color:" + c + "'><b>" + t + "</b></span>";
        // week number, Sunday-first like %U
        const jan1 = new Date(y, 0, 1);
        const week = d => Math.floor((Math.round((d - jan1) / 86400000) + 7 - d.getDay()) / 7);

        const gap = Math.max(0, Math.floor((20 - title.length) / 2));
        let out = " ".repeat(gap) + span("#bb9af7", title) + "<br>";
        out += span("#e0af68", "Su Mo Tu We Th Fr Sa") + "<br>";
        let line = "   ".repeat(first.getDay());
        for (let d = 1; d <= days; d++) {
            const date = new Date(y, m, d);
            const cell = isThisMonth && d === now.getDate()
                ? "<span style='background-color:#2ac3de;color:#1a1b26'><b><u>" + pad(d) + "</u></b></span>"
                : span("#7aa2f7", pad(d));
            line += cell;
            if (date.getDay() === 6 || d === days) {
                const fill = 6 - date.getDay();
                line += "   ".repeat(fill) + " " + span("#9ece6a", "W" + String(week(date)).padStart(2, "0"));
                out += line + (d === days ? "" : "<br>");
                line = "";
            } else {
                line += " ";
            }
        }
        return "<tt><small>" + out + "</small></tt>";
    }

    // time bold, date small and dim, as in the design
    readonly property string dim: "<span style='color:" + Theme.mix(Theme.c("text"), Theme.c("base"), 0.4) + "'>"
    text: alt ? "<b>" + Qt.formatDateTime(clock.date, "HH:mm:ss") + "</b>&nbsp;&nbsp;&nbsp;&nbsp;" + dim + Qt.formatDateTime(clock.date, "ddd d MMM yyyy") + "</span>"
              : "<b>" + Qt.formatDateTime(clock.date, "HH:mm") + "</b>&nbsp;&nbsp;&nbsp;&nbsp;" + dim + Qt.formatDateTime(clock.date, "ddd d MMM") + "</span>"
    fg: Theme.c("text")
    rl: 11
    rr: 11
    boxY: 4
    boxH: 22
    padL: 14
    padR: 14
    tip: hovered ? calendar() : ""

    onClicked: b => {
        if (b === Qt.LeftButton) alt = !alt;
    }
    onScrolled: up => shift += up ? -1 : 1
    onHoveredChanged: if (!hovered) shift = 0
}
