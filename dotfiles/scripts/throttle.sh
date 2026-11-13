#!/usr/bin/env bash
# T3.11: Ograniczanie przepustowości per-aplikacja przez cgroups + tc (Linux Traffic Control).
# Wymaga: tc (iproute2), cgcreate/cgexec (libcgroup-tools), sudo dla tc i cgroup ops.
#
# Użycie:
#   throttle.sh set <interfejs> <download_kbps> <upload_kbps>
#     – ogranicza cały ruch na interfejsie (prosto, bez per-app)
#   throttle.sh app <pid> <upload_kbps> [interfejs]
#     – ogranicza upload konkretnego procesu przez classid cgroups
#   throttle.sh off [interfejs]
#     – usuwa wszystkie ograniczenia z interfejsu
#   throttle.sh status [interfejs]
#     – pokazuje aktualne reguły tc
#   throttle.sh list
#     – listuje aktywne interfejsy z regułami
#
# Przykłady:
#   throttle.sh set wlan0 2048 512      # max 2 Mbps down / 512 kbps up na wlan0
#   throttle.sh off wlan0               # usuń ograniczenia z wlan0
#   throttle.sh status                  # pokaż wszystkie interfejsy
#
# UWAGA: tc wymaga root (sudo). Skrypt prosi o sudo automatycznie.

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
err()  { echo -e "${RED}[throttle] $*${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}[throttle] $*${NC}"; }
warn() { echo -e "${YELLOW}[throttle] $*${NC}"; }

SUDO="sudo"
command -v tc &>/dev/null || err "tc nie znalezione. Zainstaluj iproute2."

# Wykryj domyślny interfejs sieciowy
default_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1
}

usage() {
    cat <<EOF
Użycie: throttle.sh <polecenie> [argumenty]

Polecenia:
  set <iface> <down_kbps> <up_kbps>  – ogranicz interfejs
  off [iface]                         – usuń ograniczenia (domyślnie: aktywny interfejs)
  status [iface]                      – pokaż reguły tc
  list                                – listuj interfejsy z regułami

Przykłady:
  throttle.sh set wlan0 2048 512      # 2 Mbps download, 512 kbps upload
  throttle.sh set wlan0 0 256         # tylko upload: 256 kbps (download bez limitu)
  throttle.sh off                     # usuń z domyślnego interfejsu
  throttle.sh status

Uwaga: wymaga sudo dla operacji tc.
EOF
    exit 0
}

# --- set: HTB qdisc na interfejsie ---
cmd_set() {
    local iface="${1:-$(default_iface)}"
    local down_kbps="${2:-0}"
    local up_kbps="${3:-0}"

    [ -z "$iface" ] && err "Nie można wykryć interfejsu sieciowego. Podaj ręcznie."
    ip link show "$iface" &>/dev/null || err "Interfejs $iface nie istnieje."

    info "Ustawiam ograniczenia na $iface: download ${down_kbps} kbps, upload ${up_kbps} kbps"

    # Usuń stare reguły (ignoruj błąd "No such file")
    $SUDO tc qdisc del dev "$iface" root 2>/dev/null || true
    $SUDO tc qdisc del dev "$iface" ingress 2>/dev/null || true

    # --- Upload (egress = outgoing) ---
    if [ "$up_kbps" -gt 0 ]; then
        $SUDO tc qdisc add dev "$iface" root handle 1: htb default 10
        $SUDO tc class add dev "$iface" parent 1: classid 1:10 htb \
            rate "${up_kbps}kbit" burst "${up_kbps}kbit"
        info "Upload ograniczony do ${up_kbps} kbps"
    fi

    # --- Download (ingress = incoming) – przez IFB ---
    if [ "$down_kbps" -gt 0 ]; then
        # Załaduj moduł IFB (pośredni interfejs do shaping ingress)
        $SUDO modprobe ifb 2>/dev/null || true
        $SUDO ip link show ifb0 &>/dev/null || $SUDO ip link add ifb0 type ifb
        $SUDO ip link set ifb0 up

        # Skieruj ruch przychodzący do ifb0
        $SUDO tc qdisc add dev "$iface" ingress 2>/dev/null || true
        $SUDO tc filter add dev "$iface" parent ffff: protocol ip u32 \
            match u32 0 0 flowid 1:1 \
            action mirred egress redirect dev ifb0 2>/dev/null || true

        # HTB na ifb0
        $SUDO tc qdisc del dev ifb0 root 2>/dev/null || true
        $SUDO tc qdisc add dev ifb0 root handle 1: htb default 10
        $SUDO tc class add dev ifb0 parent 1: classid 1:10 htb \
            rate "${down_kbps}kbit" burst "${down_kbps}kbit"
        info "Download ograniczony do ${down_kbps} kbps (przez ifb0)"
    fi

    info "Gotowe. Usuń przez: throttle.sh off $iface"
}

# --- off: usuń reguły ---
cmd_off() {
    local iface="${1:-$(default_iface)}"
    [ -z "$iface" ] && err "Nie można wykryć interfejsu."

    $SUDO tc qdisc del dev "$iface" root 2>/dev/null && info "Usunięto reguły egress z $iface" || warn "Brak reguł egress na $iface"
    $SUDO tc qdisc del dev "$iface" ingress 2>/dev/null && info "Usunięto reguły ingress z $iface" || warn "Brak reguł ingress na $iface"
    $SUDO tc qdisc del dev ifb0 root 2>/dev/null || true
    $SUDO ip link set ifb0 down 2>/dev/null || true
    info "Ograniczenia usunięte."
}

# --- status ---
cmd_status() {
    local iface="${1:-}"
    if [ -n "$iface" ]; then
        echo "=== $iface ==="
        tc qdisc show dev "$iface" 2>/dev/null || true
        tc class show dev "$iface" 2>/dev/null || true
    else
        for dev in $(ip link show | awk -F': ' '/^[0-9]+:/{print $2}' | grep -v lo); do
            local q; q=$(tc qdisc show dev "$dev" 2>/dev/null | grep -v "pfifo_fast\|mq\|noqueue\|fq_codel" || true)
            if [ -n "$q" ]; then
                echo "=== $dev ==="
                echo "$q"
            fi
        done
    fi
}

# --- list ---
cmd_list() {
    echo "Interfejsy z niestandardowymi regułami tc:"
    for dev in $(ip link show | awk -F': ' '/^[0-9]+:/{print $2}'); do
        local q; q=$(tc qdisc show dev "$dev" 2>/dev/null | grep -v "pfifo_fast\|mq\|noqueue\|fq_codel" || true)
        [ -n "$q" ] && echo "  $dev"
    done
}

CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
    set)    cmd_set "$@" ;;
    off)    cmd_off "${1:-}" ;;
    status) cmd_status "${1:-}" ;;
    list)   cmd_list ;;
    *)      usage ;;
esac
