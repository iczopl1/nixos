pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The waybar built-ins that read /proc and /sys, polled at waybar's
// default intervals: cpu 10s, memory 2s (set in modules.json), temperature
// 10s, battery 60s.
Singleton {
    id: root

    property int cpu: 0
    property real memGb: 0
    property int tempC: 0
    property int batCap: -1
    property string batStatus: ""
    property bool acOnline: false
    property string batTime: ""

    property var _prev: null

    FileView {
        id: stat
        path: "/proc/stat"
        blockAllReads: true
    }
    FileView {
        id: meminfo
        path: "/proc/meminfo"
        blockAllReads: true
    }
    FileView {
        id: temp
        path: "/sys/class/thermal/thermal_zone4/temp"
        blockAllReads: true
    }
    FileView {
        id: bat
        path: "/sys/class/power_supply/BAT0/uevent"
        blockAllReads: true
    }
    FileView {
        id: ac
        path: "/sys/class/power_supply/AC/online"
        blockAllReads: true
    }

    function readCpu() {
        stat.reload();
        const f = stat.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + f[4];   // idle + iowait, as waybar
        const total = f.reduce((a, b) => a + b, 0);
        if (_prev) {
            const dt = total - _prev.total;
            cpu = dt > 0 ? Math.round(100 * (1 - (idle - _prev.idle) / dt)) : 0;
        }
        _prev = { idle: idle, total: total };
    }

    function readMem() {
        meminfo.reload();
        const t = meminfo.text();
        const total = Number(/MemTotal:\s+(\d+)/.exec(t)[1]);
        const avail = Number(/MemAvailable:\s+(\d+)/.exec(t)[1]);
        memGb = (total - avail) / 1048576;
    }

    function readTemp() {
        temp.reload();
        tempC = Math.round(Number(temp.text()) / 1000);
    }

    function readBat() {
        bat.reload();
        ac.reload();
        const kv = {};
        for (const l of bat.text().split("\n")) {
            const i = l.indexOf("=");
            if (i > 0) kv[l.slice(13, i)] = l.slice(i + 1);   // strip POWER_SUPPLY_
        }
        if (kv.CAPACITY === undefined) {
            batCap = -1;
            return;
        }
        batCap = Number(kv.CAPACITY);
        batStatus = kv.STATUS || "";
        acOnline = ac.text().trim() === "1";
        const now = Number(kv.CHARGE_NOW || kv.ENERGY_NOW || 0);
        const full = Number(kv.CHARGE_FULL || kv.ENERGY_FULL || 0);
        const rate = Math.abs(Number(kv.CURRENT_NOW || kv.POWER_NOW || 0));
        let h = 0;
        if (rate > 0 && batStatus === "Discharging") h = now / rate;
        else if (rate > 0 && batStatus === "Charging") h = (full - now) / rate;
        if (h > 0) {
            const total = Math.round(h * 60), hh = Math.floor(total / 60), mm = total % 60;
            batTime = hh + " h " + mm + " min";
        } else {
            batTime = "";
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.readCpu();
            root.readTemp();
        }
    }
    // second cpu sample soon after start so the first value isn't 0
    Timer {
        interval: 1000
        running: true
        onTriggered: root.readCpu()
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readMem()
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readBat()
    }
}
