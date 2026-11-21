// T2.40: bezpiecznik termiczny CPU – NIE efekt kosmetyczny, chroni sprzęt (X250 pod
// długim 100% obciążeniem, np. kompilacja full, może grzać się mocno mimo
// `services.throttled` (T1.15 – throttled naprawia tylko BIOS-owe dławienie PL1/PL2,
// nie chroni przed przegrzaniem przy realnym, długim 100% obciążeniu).
//
// Histereza: temp >= 85°C -> zapamiętaj aktualny max_perf_pct i ustaw 50% (ogranicza
// częstotliwość ogólnie, to NIE to samo co `no_turbo`/TURBO_OFF_BUILD w rebuild.sh, który
// tylko wyłącza boost i działa jedynie na czas buildu full). Trzyma 50% dopóki temp nie
// spadnie <= 70°C, potem przywraca poprzednią wartość (nie na sztywno 100 – jeśli
// użytkownik/TLP coś tam już ustawił wcześniej).
//
// Temperatura: NIE czytamy /sys/class/thermal/thermal_zone*/temp osobnym Process-em tutaj.
// `Sys.qml` (T2.33, singleton już w tym barze) robi to raz dla całego paska (najwyższa
// strefa / x86_pkg_temp, odpytywana co 10 s) i wystawia `Sys.tempC` (już w °C, nie
// milidegree) – używamy tej samej wartości, żeby nie było dwóch różnych implementacji
// czytających te same pliki sysfs.
//
// Włącznik/wyłącznik: NIE jeden z 9 "specjalnych" efektów (blur/particles/wpm-*/cava)
// gaszonych na baterii przez battery-effects-monitor.sh – to bezpiecznik sprzętowy, ma
// działać TAK SAMO na baterii jak na zasilaczu. Wzorowane na `nightlight` w
// effects-ctl.sh: osobny klucz "cpu-throttle=on|off" w ~/.config/mango-effects (plik
// LEGACY_STATE, format key=value – NIE comment-to-disable jak ~/.config/mango-effects.conf,
// tamten format jest tylko dla efektów z sekcji "specjalne"/particles/pfx). Domyślnie
// (klucz nieobecny w pliku) ochrona jest WŁĄCZONA – brak wpisu nie może wyłączać
// bezpiecznika sprzętowego.
//
// Zapis do sysfs: wymaga uprawnień zapisu do
// /sys/devices/system/cpu/intel_pstate/max_perf_pct dla usera iczo bez sudo (Quickshell
// działa jako zwykły user) – patrz systemd.tmpfiles.rules w services.nix. Na maszynie bez
// intel_pstate (inny CPU/sterownik) `cat`/`echo` na ten plik po prostu nic nie zwrócą /
// nic nie zapiszą (`|| true`) – ten komponent jest wtedy całkowicie bezczynny, bez błędów.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Wymuszane z zewnątrz (shell.qml) przez odczyt property, jak TypingGlow/Particles.
    readonly property bool active: true

    readonly property string sysfsPath: "/sys/devices/system/cpu/intel_pstate/max_perf_pct"
    readonly property string legacyState: Quickshell.env("HOME") + "/.config/mango-effects"
    readonly property int highTempC: 85
    readonly property int lowTempC: 70

    property bool enabled: true     // domyślnie ON – patrz komentarz wyżej (bezpiecznik sprzętowy)
    property bool throttled: false  // czy TO jest aktywne źródło ograniczenia teraz
    property int  savedMaxPerf: -1  // wartość max_perf_pct z chwili aktywacji, do przywrócenia

    // --- odczyt stanu toggle (cpu-throttle=on|off) z LEGACY_STATE, co 5 s ---
    Process {
        id: stateReadProc
        property string result: ""
        command: ["bash", "-c", "grep -m1 '^cpu-throttle=' " + root.legacyState + " 2>/dev/null || true"]
        running: false
        stdout: SplitParser {
            onRead: line => stateReadProc.result = line.trim()
        }
        onExited: {
            var m = stateReadProc.result.match(/^cpu-throttle=(on|off)$/)
            if (m) root.enabled = (m[1] === "on")
            // brak dopasowania (klucz nieobecny) -> zostaje poprzednia wartość `enabled`
            // (domyślnie true od startu singletona)
            root._afterStateRead()
        }
    }

    // --- odczyt aktualnego max_perf_pct, tylko przy pierwszej aktywacji (zanim nadpiszemy) ---
    Process {
        id: readMaxProc
        property string result: ""
        property int tempAtActivation: 0
        command: ["bash", "-c", "cat " + root.sysfsPath + " 2>/dev/null || true"]
        running: false
        stdout: SplitParser {
            onRead: line => readMaxProc.result = line.trim()
        }
        onExited: {
            var v = parseInt(readMaxProc.result)
            if (isNaN(v)) return   // brak pliku / nie intel_pstate -> nic do zrobienia
            root.savedMaxPerf = v
            root.throttled = true
            root._writeMaxPerf(50)
            root._log("aktywacja: temp=" + readMaxProc.tempAtActivation + "C, max_perf_pct " + v + "% -> 50%")
        }
    }

    // --- wspólne procesy do zapisu sysfs i logowania (komenda ustawiana przed każdym użyciem) ---
    Process { id: writeProc }
    Process { id: logProc }

    function _writeMaxPerf(pct) {
        writeProc.command = ["bash", "-c", "echo " + pct + " > " + root.sysfsPath + " 2>/dev/null || true"]
        writeProc.running = false
        writeProc.running = true
    }

    function _log(msg) {
        logProc.command = ["logger", "-t", "thermal-throttle", msg]
        logProc.running = false
        logProc.running = true
    }

    function activate(tempC) {
        readMaxProc.tempAtActivation = tempC
        readMaxProc.running = false
        readMaxProc.running = true
    }

    function restore(reason) {
        var v = root.savedMaxPerf > 0 ? root.savedMaxPerf : 100
        root._writeMaxPerf(v)
        root._log("dezaktywacja (" + reason + "): max_perf_pct -> " + v + "%")
        root.throttled = false
        root.savedMaxPerf = -1
    }

    function _afterStateRead() {
        if (!root.enabled) {
            if (root.throttled) root.restore("effects cpu-throttle off")
            return
        }
        var t = Sys.tempC
        if (!root.throttled && t >= root.highTempC) {
            root.activate(t)
        } else if (root.throttled && t <= root.lowTempC) {
            root.restore("temperatura spadla do " + t + "C")
        }
        // 70 < t < 85 (albo throttled i t > 70, albo nie-throttled i t < 85): bez zmian
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stateReadProc.running = false
            stateReadProc.running = true
        }
    }
}
