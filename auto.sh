#!/usr/bin/env bash
# auto.sh – instalator NixOS na nową maszynę (MASTER.md §2)
#
# Użycie (z chroot po nixos-install lub z działającego systemu):
#   ./auto.sh
#
# Co robi:
#   1. Sprawdza UEFI i brak szyfrowania
#   2. Wykrywa czy to nowa maszyna (UUID /)
#   3. Na nowej maszynie:
#      a. Zgaduje partycje EFI i swap, pyta o potwierdzenie
#      b. Pyta: minimal czy full? (pokazuje GB do pobrania)
#      c. Zapisuje PROFILE, TURBO_OFF_BUILD jeśli potrzeba
#   4. Stawia minimal (boot)
#   5. Jeśli wybrano full → stawia full w tle (z działającego systemu)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"

# --- Kolory ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
err()     { echo -e "${RED}[BŁĄD] $*${RESET}" >&2; }
warn()    { echo -e "${YELLOW}[UWAGA] $*${RESET}"; }
ok()      { echo -e "${GREEN}[OK] $*${RESET}"; }
info()    { echo -e "${CYAN}$*${RESET}"; }
section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }
ask()     { echo -en "${BOLD}$*${RESET}"; }

# ---------------------------------------------------------------------------
# 0. Ochrona przed nadpisaniem repo z zewnątrz (Syncthing, stara karta SD itp.)
#
# Incydent 2026-11-20 (zob. BROKEN.md): folder zawierający to repo był
# zsynchronizowany przez Syncthing (sendreceive) z inną maszyną, która miała
# zamrożoną kopię projektu z 6 października (epoka flake+home-manager+NvChad).
# Syncthing nadpisał żywe pliki tą starą kopią – wskrzesił dawno usunięte
# pliki (flake.nix, home.nix, hosts/, modules/, comand.sh, logs.txt) i cofnął
# treść części innych (np. dotfiles/nvim/init.lua wrócił do bootowania NvChad).
# Działo się to też W TRAKCIE naprawy – każda kolejna edycja była nadpisywana
# ponownie, dopóki folder Syncthing nie został ręcznie wstrzymany.
#
# Dwa sprawdzenia poniżej wykrywają odcisk tego konkretnego typu incydentu
# (nie ogólne "coś się zmieniło") i ZATRZYMUJĄ auto.sh, zanim dojdzie do
# builda/commita/skopiowania zepsutej treści do /etc/nixos. Trzecie tylko
# ostrzega – auto.sh ma działać też bez Syncthing/bez dostępu do jego API.
# ---------------------------------------------------------------------------
section "Sprawdzam, czy repo nie zostało nadpisane z zewnątrz"

# a) Znane, dawno usunięte pliki z epoki flake+home-manager+NvChad. Ich
#    ponowne pojawienie się praktycznie na pewno oznacza nadpisanie starą
#    kopią, nie świadomą pracę nad configiem.
RESURRECTED=()
for f in flake.nix flake.lock home.nix hosts modules comand.sh logs.txt; do
  if [[ -e "$REPO_DIR/$f" ]]; then
    RESURRECTED+=("$f")
  fi
done
if [[ ${#RESURRECTED[@]} -gt 0 ]]; then
  err "Wykryto zmartwychwstałe pliki z bardzo starej wersji configu: ${RESURRECTED[*]}"
  err "To już się zdarzyło 2026-11-20 (zob. BROKEN.md) – zewnętrzna synchronizacja"
  err "nadpisała repo starą kopią. NIE kontynuuję (żadnego builda/commita/kopiowania"
  err "do /etc/nixos). Sprawdź Syncthing (czy folder zawierający $REPO_DIR jest"
  err "w trybie sendreceive z nieznanym/starym urządzeniem) i zbadaj przyczynę,"
  err "zanim usuniesz te pliki ręcznie."
  exit 1
fi

# b) CRLF w śledzonych plikach wykonywalnych (.sh) – odcisk tego samego
#    incydentu (nośnik/urządzenie dotykane po stronie Windows), i realny
#    powód crashy (CRLF po "{" w bashu to syntax error, zob. BROKEN.md).
#    TYLKO ostrzeżenie, nie blokada: repo ma sporo starych, potwierdzonych
#    martwych plików (dotfiles/bash, dotfiles/cava, dotfiles/rofi, część
#    dotfiles/waybar) z CRLF od zawsze, niezwiązanych z żadnym incydentem –
#    twarda blokada na to by trwale zablokowała auto.sh/rebuild.sh, dopóki
#    ktoś nie posprząta całego tego balastu. grep -U: wyłącza tłumaczenie
#    CRLF przy odczycie, inaczej dopasowanie $'\r' bywa niewiarygodne.
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  CRLF_SH=()
  while IFS= read -r f; do
    [[ -f "$REPO_DIR/$f" ]] || continue
    if grep -qU $'\r' "$REPO_DIR/$f" 2>/dev/null; then
      CRLF_SH+=("$f")
    fi
  done < <(git -C "$REPO_DIR" ls-files -- '*.sh')
  if [[ ${#CRLF_SH[@]} -gt 0 ]]; then
    warn "Końcówki linii CRLF w ${#CRLF_SH[@]} śledzonych skryptach .sh – może to być"
    warn "odcisk nadpisania repo z zewnątrz (zob. BROKEN.md, incydent 2026-11-20) albo"
    warn "stary, znany balast. Sprawdź przed dalszą pracą, zwłaszcza jeśli dotyczy"
    warn "skryptu realnie używanego: ${CRLF_SH[*]:0:5}"
  fi
fi
ok "Brak oznak zmartwychwstałych plików z martwej epoki configu"

# c) Syncthing: tylko ostrzeżenie (nie blokada), jeśli demon działa i folder
#    obejmujący REPO_DIR nie jest wstrzymany – ryzyko nadpisania W TRAKCIE
#    buildu przez inne podłączone urządzenie.
if pgrep -x syncthing >/dev/null 2>&1; then
  ST_CONFIG="${HOME}/.config/syncthing/config.xml"
  if [[ -f "$ST_CONFIG" ]] && command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    ST_API_KEY=$(grep -o '<apikey>[^<]*</apikey>' "$ST_CONFIG" 2>/dev/null | sed 's/<[^>]*>//g')
    if [[ -n "$ST_API_KEY" ]]; then
      ST_FOLDERS=$(curl -s --max-time 2 -H "X-API-Key: $ST_API_KEY" \
        "http://127.0.0.1:8384/rest/config/folders" 2>/dev/null || true)
      if [[ -n "$ST_FOLDERS" ]]; then
        RISK=$(REPO_DIR="$REPO_DIR" python3 -c '
import json, os, sys
repo = os.environ["REPO_DIR"]
try:
    folders = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
for f in folders:
    p = os.path.realpath(f.get("path", ""))
    if p and (repo == p or repo.startswith(p + "/")) and not f.get("paused", False):
        print(f.get("label") or f.get("id"))
' <<<"$ST_FOLDERS" 2>/dev/null || true)
        if [[ -n "$RISK" ]]; then
          warn "Syncthing aktywnie synchronizuje folder \"$RISK\", który obejmuje to repo."
          warn "Jeśli inne podłączone urządzenie ma starą/zamrożoną kopię tego projektu,"
          warn "może nadpisać zmiany w trakcie buildu (zob. incydent 2026-11-20, BROKEN.md)."
          warn "Rozważ wstrzymanie tego folderu w Syncthing na czas pracy nad repo."
        fi
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 1. UEFI
# ---------------------------------------------------------------------------
section "Sprawdzam tryb uruchomienia"
if [[ ! -d /sys/firmware/efi ]]; then
  err "System uruchomiony w trybie BIOS/Legacy – wymagany UEFI."
  err "Włącz UEFI w ustawieniach BIOS i uruchom ponownie."
  exit 1
fi
ok "UEFI OK"

# ---------------------------------------------------------------------------
# 2. Brak szyfrowania (MASTER §3)
# ---------------------------------------------------------------------------
section "Sprawdzam brak szyfrowania dysku"
ROOT_DEV=$(findmnt -n -o SOURCE /)
if lsblk -n -o FSTYPE "$ROOT_DEV" 2>/dev/null | grep -q "crypto_LUKS"; then
  err "Partycja / jest na LUKS. Branch 'main' nie obsługuje szyfrowania (MASTER §3)."
  err "Użyj osobnego brancha z szyfrowaniem."
  exit 1
fi
ok "Brak szyfrowania OK"

# ---------------------------------------------------------------------------
# 3. Czy to nowa maszyna?
# ---------------------------------------------------------------------------
section "Wykrywanie maszyny"

CURRENT_HW="$NIXOS_DIR/hardware-configuration.nix"
NEW_HW="/tmp/auto-hw-$(date +%s).nix"

# Generuj świeży hardware config do pliku tymczasowego
if ! nixos-generate-config --show-hardware-config > "$NEW_HW" 2>/dev/null; then
  # Fallback – jesteśmy w chroot bez zamontowanego /boot/efi
  warn "nixos-generate-config --show-hardware-config nie powiodło się. Spróbuję z generowaniem do /etc/nixos..."
  nixos-generate-config 2>/dev/null || true
  cp "$CURRENT_HW" "$NEW_HW" 2>/dev/null || true
fi

NEW_MACHINE=0
if [[ ! -f "$CURRENT_HW" ]]; then
  info "Brak $CURRENT_HW – nowa maszyna."
  NEW_MACHINE=1
else
  # hardware-configuration.nix ma wieloliniowy format, grep musi wybrać blok "/" a potem device
  extract_root_uuid() {
    local f="$1"
    # Znajdź linię z device = "..." w sekcji fileSystems."/" (zakładamy < 10 linii po nagłówku)
    awk '/fileSystems\."\/"/,/^\s*};/' "$f" 2>/dev/null \
      | grep 'device\s*=' \
      | grep -oP 'by-uuid/\K[^"]+' \
      | head -1
  }
  OLD_UUID=$(extract_root_uuid "$CURRENT_HW")
  NEW_UUID=$(extract_root_uuid "$NEW_HW")

  if [[ -z "$OLD_UUID" || -z "$NEW_UUID" ]]; then
    warn "Nie mogę porównać UUID / – przyjmuję nową maszynę dla bezpieczeństwa."
    NEW_MACHINE=1
  elif [[ "$OLD_UUID" != "$NEW_UUID" ]]; then
    info "UUID / różny (stary: $OLD_UUID, nowy: $NEW_UUID) – nowa maszyna."
    NEW_MACHINE=1
  else
    ok "Znana maszyna (UUID / zgadza się: $NEW_UUID). Zwykła aktualizacja."
  fi
fi

# ---------------------------------------------------------------------------
# ZNANA MASZYNA – tylko rebuild
# ---------------------------------------------------------------------------
if [[ "$NEW_MACHINE" -eq 0 ]]; then
  section "Aktualizacja konfiguracji"

  if [[ ! -f "$NIXOS_DIR/PROFILE" ]]; then
    warn "Brak $NIXOS_DIR/PROFILE – przyjmuję 'full'. Ustaw ręcznie: echo minimal | sudo tee $NIXOS_DIR/PROFILE"
  fi

  # Jeśli brak PROFILE – zapytaj użytkownika i utwórz plik.
  if [[ ! -f "$NIXOS_DIR/PROFILE" ]]; then
    warn "Brak $NIXOS_DIR/PROFILE."
    ask "Który profil budować? [minimal/full] (Enter = full): "
    read -r PROFILE_ANSWER
    PROFILE_ANSWER="${PROFILE_ANSWER,,}"
    if [[ "$PROFILE_ANSWER" == "minimal" ]]; then
      echo "minimal" | sudo tee "$NIXOS_DIR/PROFILE" > /dev/null
      ok "PROFILE = minimal"
    else
      echo "full" | sudo tee "$NIXOS_DIR/PROFILE" > /dev/null
      ok "PROFILE = full"
    fi
  fi

  # Deleguj do rebuild.sh – ma sprawdzoną logikę budowania (nix-build przez kanał nixos).
  # rebuild.sh sam czyta PROFILE, robi sprawdzenia, commit (jeśli są zmiany) i kopiowanie.
  # Opis commitu generujemy automatycznie z listy zmienionych plików.
  # Uwaga: grep na pustym wejściu zwraca 1 → używamy || true żeby nie wywołać set -e.
  AUTO_CHANGED=$(git -C "$REPO_DIR" diff --name-only HEAD 2>/dev/null \
    | head -4 | paste -sd ',' | sed 's/,/, /g' || true)
  if [[ -z "$AUTO_CHANGED" ]]; then
    AUTO_CHANGED=$(git -C "$REPO_DIR" status --short 2>/dev/null \
      | awk '{print $2}' | head -4 | paste -sd ',' | sed 's/,/, /g' || true)
  fi
  AUTO_MSG="auto: ${AUTO_CHANGED:-synchronizacja konfiguracji}"
  info "Uruchamiam rebuild.sh (commit: \"$AUTO_MSG\")..."
  exec "$REPO_DIR/rebuild.sh" "$AUTO_MSG"
fi

# ---------------------------------------------------------------------------
# NOWA MASZYNA
# ---------------------------------------------------------------------------
section "Nowa maszyna – konfiguracja"

# --- 3a. Partycja EFI ---
section "Wykrywanie partycji EFI (Linux)"

# Zbierz kandydatów EFI: typ partycji EFI System lub vfat ~100MB-2GB, bez Microsoft
EFI_CANDIDATES=()
while IFS= read -r line; do
  DEV=$(echo "$line" | awk '{print $1}')
  SIZE=$(echo "$line" | awk '{print $2}')
  FSTYPE=$(echo "$line" | awk '{print $3}')
  PARTTYPE=$(echo "$line" | awk '{print $4}')
  MOUNTPOINT=$(echo "$line" | awk '{print $5}')

  # Pomiń, jeśli jest już zamontowana jako /boot/efi Windowsa
  if [[ -n "$MOUNTPOINT" && "$MOUNTPOINT" == /boot* ]]; then
    # Sprawdź czy to ESP Windowsa
    if ls "${MOUNTPOINT}/EFI/" 2>/dev/null | grep -qi "Microsoft"; then
      continue
    fi
  fi
  # Pomiń partycje NTFS/Windows
  [[ "$FSTYPE" == "ntfs" ]] && continue

  # Kandydat: typ EFI System albo vfat
  if [[ "$PARTTYPE" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] || [[ "$FSTYPE" == "vfat" ]]; then
    EFI_CANDIDATES+=("$DEV")
  fi
done < <(lsblk -lp -n -o NAME,SIZE,FSTYPE,PARTTYPE,MOUNTPOINT | grep -v "^$")

# Sprawdź, które kandydaty mają katalog EFI/Microsoft (to ESP Windowsa)
EFI_LINUX=()
EFI_WINDOWS=()
for c in "${EFI_CANDIDATES[@]}"; do
  TMPMT=$(mktemp -d)
  if sudo mount -o ro "$c" "$TMPMT" 2>/dev/null; then
    if ls "$TMPMT/EFI/" 2>/dev/null | grep -qi "Microsoft"; then
      EFI_WINDOWS+=("$c")
    else
      EFI_LINUX+=("$c")
    fi
    sudo umount "$TMPMT" 2>/dev/null || true
  else
    # Nie da się zamontować – zakładamy kandydat (niesformatowana)
    EFI_LINUX+=("$c")
  fi
  rmdir "$TMPMT" 2>/dev/null || true
done

echo ""
info "Kandydaci EFI Linuksa: ${EFI_LINUX[*]:-brak}"
info "Pominięte (ESP Windowsa): ${EFI_WINDOWS[*]:-brak}"

if [[ ${#EFI_LINUX[@]} -eq 1 ]]; then
  EFI_PART="${EFI_LINUX[0]}"
  info "Wykryto partycję EFI Linuksa: $EFI_PART"
  ask "Potwierdzasz? [T/n]: "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    ask "Podaj urządzenie EFI (np. /dev/sda1): "
    read -r EFI_PART
  fi
elif [[ ${#EFI_LINUX[@]} -eq 0 ]]; then
  warn "Nie znaleziono partycji EFI. Upewnij się, że jest sformatowana jako FAT32 i zamontowana w /boot/efi."
  ask "Podaj urządzenie EFI (np. /dev/sda1): "
  read -r EFI_PART
else
  info "Znaleziono wiele kandydatów:"
  for i in "${!EFI_LINUX[@]}"; do
    echo "  $((i+1)). ${EFI_LINUX[$i]}"
    lsblk -lp -n -o NAME,SIZE,FSTYPE,LABEL "${EFI_LINUX[$i]}" | sed 's/^/     /'
  done
  ask "Wybierz numer: "
  read -r NUM
  EFI_PART="${EFI_LINUX[$((NUM-1))]}"
fi

ok "Wybrana partycja EFI: $EFI_PART"

# --- 3b. Partycja swap ---
section "Wykrywanie swap"

SWAP_PART=""
# Sprawdź aktywny swap
ACTIVE_SWAP=$(swapon --show=NAME --noheadings 2>/dev/null | head -1 || true)
if [[ -n "$ACTIVE_SWAP" ]]; then
  SWAP_PART="$ACTIVE_SWAP"
  info "Aktywny swap: $SWAP_PART"
else
  # Szukaj po typie partycji GPT swap
  SWAP_CAND=$(lsblk -lp -n -o NAME,PARTTYPE,FSTYPE 2>/dev/null \
    | awk '$2=="0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" || $3=="swap" {print $1}' \
    | head -1 || true)
  if [[ -n "$SWAP_CAND" ]]; then
    SWAP_PART="$SWAP_CAND"
    info "Wykryto partycję swap: $SWAP_PART"
  else
    warn "Nie znaleziono partycji swap. Możesz użyć swapfile lub zram."
  fi
fi

if [[ -n "$SWAP_PART" ]]; then
  ask "Potwierdzasz swap=$SWAP_PART? [T/n/pomiń]: "
  read -r SW_CONF
  [[ "$SW_CONF" =~ ^[Nn]$ ]] && SWAP_PART=""
  [[ "$SW_CONF" =~ ^[Pp] ]] && SWAP_PART=""
fi

# --- 3c. Montowanie EFI przed generowaniem hardware config ---
section "Montowanie EFI"
if ! mountpoint -q /boot/efi 2>/dev/null; then
  sudo mkdir -p /boot/efi
  sudo mount "$EFI_PART" /boot/efi
  ok "Zamontowano $EFI_PART w /boot/efi"
else
  CURRENT_EFI=$(findmnt -n -o SOURCE /boot/efi || true)
  if [[ "$CURRENT_EFI" != "$EFI_PART" ]]; then
    warn "/boot/efi jest już zamontowane jako $CURRENT_EFI (oczekiwano $EFI_PART). Kontynuuję."
  else
    ok "/boot/efi już zamontowane"
  fi
fi

# --- 3d. Generuj hardware-configuration.nix ---
section "Generowanie hardware-configuration.nix"
sudo nixos-generate-config 2>&1
# Zweryfikuj, że /boot/efi jest wpisane z fsType = "vfat"
if ! grep -q '/boot/efi' "$CURRENT_HW" 2>/dev/null; then
  err "hardware-configuration.nix nie zawiera /boot/efi. Coś poszło nie tak z montowaniem."
  err "Sprawdź ręcznie: cat $CURRENT_HW"
  exit 1
fi
ok "hardware-configuration.nix wygenerowany"

# --- 3e. ThinkPad X250 / starszy sprzęt – TURBO_OFF_BUILD ---
section "Sprawdzam sprzęt (turbo na czas buildu)"
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || true)
info "CPU: $CPU_MODEL"

TURBO_SUGGEST=0
# Heurystyka: i5/i7/i3 5xxx = Broadwell (5. gen), 4xxx = Haswell, 3xxx = Ivy Bridge itp.
if echo "$CPU_MODEL" | grep -qiE 'i[357]-[2345][0-9]{3}'; then
  TURBO_SUGGEST=1
  warn "Wykryto starszy procesor Intel (Haswell/Ivy Bridge/Broadwell lub starszy)."
  warn "Zalecane: wyłączanie turbo na czas budowania full (ochrona termiczna, MASTER §5)."
fi

TURBO_OFF=0
if [[ "$TURBO_SUGGEST" -eq 1 ]]; then
  ask "Włączyć TURBO_OFF_BUILD dla tego sprzętu? [T/n]: "
  read -r T_CONF
  [[ ! "$T_CONF" =~ ^[Nn]$ ]] && TURBO_OFF=1
else
  ask "Chcesz włączyć TURBO_OFF_BUILD (wyłączenie turbo na czas buildu full)? [t/N]: "
  read -r T_CONF
  [[ "$T_CONF" =~ ^[Tt]$ ]] && TURBO_OFF=1
fi

if [[ "$TURBO_OFF" -eq 1 ]]; then
  echo "1" | sudo tee "$NIXOS_DIR/TURBO_OFF_BUILD" > /dev/null
  ok "TURBO_OFF_BUILD ustawiony"
fi

# --- 3f. Minimal czy full? ---
section "Wybór profilu"

# Dry-build minimalny – ile GB do pobrania
info "Liczę przybliżony rozmiar pobrania dla profilu minimal..."
MIN_ENTRY="$REPO_DIR/configuration_minimal.nix"
FULL_ENTRY="$REPO_DIR/configuration.nix"

get_download_size() {
  local entry="$1"
  # nix-build dry-run wypisuje "will be fetched (X MiB download)"
  sudo nix-build /nix/var/nix/profiles/per-user/root/channels/nixos/nixos \
    --attr config.system.build.toplevel \
    -I nixos-config="$entry" \
    --dry-run 2>&1 \
    | grep -oP '\d+\.\d+ MiB download' \
    | tail -1 || echo "?"
}

echo ""
info "Profil minimal – wymagania:"
MIN_SIZE=$(get_download_size "$MIN_ENTRY")
echo "  Pobieranie: ~$MIN_SIZE"
echo "  Czas ~8 MB/s: ok. 1h (razem z rozpakowaniem)"
echo ""
info "  Zawiera: GUI (Mango), terminal, przeglądarka, KeePassXC, Claude Code, nvim, git"
echo ""

info "Profil full – wymagania:"
FULL_SIZE=$(get_download_size "$FULL_ENTRY")
echo "  Pobieranie: ~$FULL_SIZE"
echo "  Czas na X250: ok. 4h+ (kompilacja Quickshell, crafts, narzędzia)"
echo ""
info "  Zawiera: wszystko z minimal + crafts, python ML, narzędzia embedded, itd."
echo ""
info "  UWAGA: przy wyborze full – instalator najpierw stawia minimal,"
info "  a full buduje dopiero po uruchomieniu (w tle, nie blokuje pracy)."
echo ""

ask "Wybierz profil [minimal/full]: "
read -r PROFILE_CHOICE
PROFILE_CHOICE="${PROFILE_CHOICE,,}"  # lowercase

if [[ "$PROFILE_CHOICE" != "minimal" && "$PROFILE_CHOICE" != "full" ]]; then
  warn "Nieznany wybór '$PROFILE_CHOICE' – przyjmuję 'minimal'."
  PROFILE_CHOICE="minimal"
fi

echo "$PROFILE_CHOICE" | sudo tee "$NIXOS_DIR/PROFILE" > /dev/null
ok "PROFILE = $PROFILE_CHOICE"

# ---------------------------------------------------------------------------
# 4. INSTALACJA – zawsze zaczynamy od minimal
# ---------------------------------------------------------------------------
section "Kopiowanie konfiguracji do $NIXOS_DIR"
sudo mkdir -p "$NIXOS_DIR"
sudo rsync -a \
  --exclude=".git/" \
  --exclude="hardware-configuration.nix" \
  "$REPO_DIR/" "$NIXOS_DIR/"
ok "Konfiguracja skopiowana"

section "Budowanie i instalacja minimal"
info "Profil minimal zawsze jako pierwszy krok (bootowalny system, MASTER §2)."

# Sprawdź czy jesteśmy w chroot (nixos-install) czy w działającym systemie
IN_CHROOT=0
if [[ "$(stat -c %d:%i /)" == "$(stat -c %d:%i /proc/1/root/. 2>/dev/null || echo x)" ]]; then
  IN_CHROOT=0
elif [[ -f /etc/NIXOS ]]; then
  # Działający NixOS – używamy nixos-rebuild
  IN_CHROOT=0
elif ! mountpoint -q /proc; then
  IN_CHROOT=1
fi

NIXPKGS_CHAN="/nix/var/nix/profiles/per-user/root/channels/nixos"
[[ ! -d "$NIXPKGS_CHAN" ]] && NIXPKGS_CHAN=$(sudo nix-instantiate --find-file nixpkgs 2>/dev/null || true)

if [[ -z "$NIXPKGS_CHAN" || ! -d "$NIXPKGS_CHAN" ]]; then
  err "Nie mogę znaleźć nixpkgs. Ustaw kanał: sudo nix-channel --add https://nixos.org/channels/nixos-26.05 nixos && sudo nix-channel --update"
  exit 1
fi

build_and_activate_boot() {
  # nixos-rebuild boot --file: jedyny pewny sposób na NixOS 26.05+ (nixos-rebuild-ng/Python).
  # nixos-rebuild-ng ignoruje nixos-config w NIX_PATH, wymaga --file.
  local entry="$1"
  sudo env \
    NIX_PATH="nixpkgs=$NIXPKGS_CHAN" \
    nixos-rebuild boot --no-flake --file "$entry"
}

if [[ "$IN_CHROOT" -eq 1 ]]; then
  info "Tryb chroot – używam nixos-install"
  SYSTEM_DRV=$(sudo nix-build "$NIXPKGS_CHAN/nixos" \
    --attr config.system.build.toplevel \
    -I nixos-config="$NIXOS_DIR/configuration_minimal.nix" \
    --no-out-link 2>&1)
  sudo nixos-install --no-channel-copy --system "$SYSTEM_DRV"
else
  info "Tryb normalny – nix-build przez kanał nixos"
  echo "minimal" | sudo tee "$NIXOS_DIR/PROFILE" > /dev/null
  build_and_activate_boot "$NIXOS_DIR/configuration_minimal.nix"
fi

ok "Minimal zainstalowany (lub zaplanowany do bootowania)"

# --- Weryfikacja bootloadera ---
section "Weryfikacja bootloadera"
if [[ -d /boot/efi/EFI ]]; then
  ok "Katalog /boot/efi/EFI istnieje"
  ls /boot/efi/EFI/
else
  warn "Nie znaleziono /boot/efi/EFI – weryfikacja bootloadera po restarcie."
fi

# ---------------------------------------------------------------------------
# 5. Full w tle (jeśli wybrany)
# ---------------------------------------------------------------------------
if [[ "$PROFILE_CHOICE" == "full" ]]; then
  section "Full – budowanie po uruchomieniu systemu"
  info "Minimal jest gotowy. Full będzie zbudowane AUTOMATYCZNIE po pierwszym uruchomieniu."
  info ""
  info "Żeby to zrobić – po restarcie do minimal uruchom:"
  info "  cd '$REPO_DIR' && ./rebuild.sh --full \"feat: przejście na full\""
  info ""
  info "Albo uruchom teraz w tle (jeśli jesteś w działającym systemie, nie chroot):"

  if [[ "$IN_CHROOT" -eq 0 ]]; then
    ask "Zbudować full w tle teraz? (musi działać X/Wayland lub SSH) [t/N]: "
    read -r BUILD_FULL_NOW
    if [[ "$BUILD_FULL_NOW" =~ ^[Tt]$ ]]; then
      info "Uruchamiam rebuild full w tle... Log: /tmp/auto-full-build.log"
      nohup bash -c \
        "cd '$REPO_DIR' && ./rebuild.sh --full 'feat: instalacja full' > /tmp/auto-full-build.log 2>&1" \
        &
      ok "Full w tle (PID $!). Sprawdź log: tail -f /tmp/auto-full-build.log"
    fi
  else
    warn "Jesteśmy w chroot – nie mogę uruchomić full w tle. Zrób to po restarcie."
  fi
fi

# ---------------------------------------------------------------------------
# 6. Podsumowanie
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo -e "${GREEN}${BOLD}  Instalacja zakończona!${RESET}"
echo -e "${GREEN}  Profil: $PROFILE_CHOICE${RESET}"
echo -e "${GREEN}  Partycja EFI: $EFI_PART${RESET}"
[[ -n "$SWAP_PART" ]] && echo -e "${GREEN}  Swap: $SWAP_PART${RESET}"
echo -e "${GREEN}${BOLD}================================================${RESET}"
echo ""
info "Następne kroki:"
echo "  1. Uruchom ponownie: systemctl reboot"
echo "  2. Zaloguj się, sprawdź czy claude działa: claude"
echo "  3. Sprawdź pasek Quickshell i Mango"
if [[ "$PROFILE_CHOICE" == "full" ]]; then
  echo "  4. Zbuduj full: cd '$REPO_DIR' && ./rebuild.sh --full \"feat: full install\""
fi
echo ""
