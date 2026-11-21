import QtQuick
import Quickshell

// clock: left click opens the month calendar (CalendarPopup), right click
// swaps to the long format with seconds.
Seg {
    id: root

    property bool alt: false

    SystemClock {
        id: clock
        precision: root.alt ? SystemClock.Seconds : SystemClock.Minutes
    }

    CalendarPopup {
        id: cal
        target: root
        clockHovered: root.hovered
    }

    // time bold, date small and dim, as in the design
    readonly property string dim: "<span style='color:" + Theme.mix(Theme.flowAt(0.5), Theme.c("base"), 0.35) + "'>"
    text: alt ? "<b>" + Qt.formatDateTime(clock.date, "HH:mm:ss") + "</b>&nbsp;&nbsp;&nbsp;&nbsp;" + dim + Qt.formatDateTime(clock.date, "ddd d MMM yyyy") + "</span>"
              : "<b>" + Qt.formatDateTime(clock.date, "HH:mm") + "</b>&nbsp;&nbsp;&nbsp;&nbsp;" + dim + Qt.formatDateTime(clock.date, "ddd d MMM") + "</span>"
    fg: Theme.flowAt(0.5)
    rl: 11
    rr: 11
    boxY: 4
    boxH: 22
    padL: 14
    padR: 14

    // left click: calendar; right click: seconds and year
    onClicked: b => {
        if (b === Qt.LeftButton) cal.toggle();
        else if (b === Qt.RightButton) alt = !alt;
    }
    onScrolled: up => { if (cal.visible) cal.shift += up ? -1 : 1; }
}
