#!/usr/bin/env bash
# rebuild.sh – przebudowa konfiguracji NixOS
#
# Workflow (MASTER.md §6):
#   sprawdzenia → build boot → commit → kopiowanie do /etc/nixos
#
# WAŻNE: Agent (Claude Code) ZAWSZE używa tego skryptu (tryb boot).
# Użytkownik może używać "sudo nixos-rebuild switch" bezpośrednio.
#
# Użycie:
#   ./rebuild.sh "opis zmiany"          – pełny workflow
#   ./rebuild.sh -n "opis"              – dry-build (bez commitu)
#   ./rebuild.sh --full "opis"          – przejście z minimal na full
#   ./rebuild.sh -h                     – pomoc

set -euo pipefail

# --- Ścieżki ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"
PROFILE_FILE="$NIXOS_DIR/PROFILE"
TURBO_FILE="$NIXOS_DIR/TURBO_OFF_BUILD"
NO_TURBO="/sys/devices/system/cpu/intel_pstate/no_turbo"

# --- Kolory ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
err()     { echo -e "${RED}[BŁĄD] $*${RESET}" >&2; }
warn()    { echo -e "${YELLOW}[UWAGA] $*${RESET}"; }
ok()      { echo -e "${GREEN}[OK] $*${RESET}"; }
section() { echo -e "\n${CYAN}--- $* ---${RESET}"; }

# --- Parsowanie argumentów ---
DRY=0
FORCE_FULL=0
COMMIT_MSG=""

usage() {
  cat <<EOF
Użycie: $0 [opcje] "opis zmiany"

Opcje:
  -n, --dry-run   dry-build: sprawdza co zostanie pobrane/skompilowane, bez zmian
  --full          przejście z minimal na full (zmienia PROFILE po udanym buildzie)
  -h, --help      ta pomoc

Przykłady:
  ./rebuild.sh "feat: kernel zen"
  ./rebuild.sh -n "test dry-run"
  ./rebuild.sh --full "przejście na full"
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY=1; shift ;;
    --full)       FORCE_FULL=1; shift ;;
    -h|--help)    usage ;;
    -*)           err "Nieznana opcja: $1"; exit 1 ;;
    *)            COMMIT_MSG="$1"; shift ;;
  esac
done

if [[ -z "$COMMIT_MSG" && "$DRY" -eq 0 ]]; then
  err "Podaj opis zmiany jako argument (lub użyj -n dla dry-run)."
  echo "Przykład: $0 \"feat: dodano kernel zen\""
  exit 1
fi

# --- Wybór profilu i pliku wejściowego ---
section "Profil"
if [[ -f "$PROFILE_FILE" ]]; then
  PROFILE=$(cat "$PROFILE_FILE")
else
  warn "Brak $PROFILE_FILE – przyjmuję 'full' (configuration.nix)"
  PROFILE="full"
fi

[[ "$FORCE_FULL" -eq 1 ]] && PROFILE="full"

if [[ "$PROFILE" == "minimal" && -f "$REPO_DIR/configuration_minimal.nix" ]]; then
  ENTRY="$REPO_DIR/configuration_minimal.nix"
elif [[ -f "$REPO_DIR/configuration.nix" ]]; then
  ENTRY="$REPO_DIR/configuration.nix"
else
  err "Brak pliku wejściowego. Sprawdź $REPO_DIR."
  exit 1
fi

echo "  Profil : $PROFILE"
echo "  Wejście: $ENTRY"

# --- 1. Sprawdzenie składni .nix ---
section "Sprawdzanie składni .nix"
SYNTAX_ERR=0
while IFS= read -r -d '' f; do
  if ! nix-instantiate --parse "$f" > /dev/null 2>&1; then
    err "Błąd składni: $f"
    nix-instantiate --parse "$f" 2>&1 | head -5 >&2
    SYNTAX_ERR=1
  fi
done < <(find "$REPO_DIR" -name "*.nix" -not -path "*/.git/*" -not -path "*/vendor/*" -print0)
[[ "$SYNTAX_ERR" -eq 1 ]] && exit 1
ok "Składnia poprawna"

# --- 2. Lintery (ostrzeżenia, nie blokują buildu) ---
if command -v statix > /dev/null 2>&1; then
  section "statix check"
  statix check "$REPO_DIR" 2>&1 || warn "statix zgłosił ostrzeżenia (nie blokuje)"
fi
if command -v deadnix > /dev/null 2>&1; then
  section "deadnix"
  deadnix "$REPO_DIR" 2>&1 || warn "deadnix zgłosił ostrzeżenia (nie blokuje)"
fi

# --- 3. Sprawdzenia bezpieczeństwa ---
section "Bezpieczeństwo"
SEC_ERR=0

# Brak szyfrowania dysku w main (MASTER §10)
BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$BRANCH" == "main" ]]; then
  if grep -rql "luks\|Cryptodisk\|randomEncryption" "$REPO_DIR"/*.nix 2>/dev/null; then
    err "Znaleziono opcje szyfrowania dysku w branchu main (MASTER złota reguła 10)"
    SEC_ERR=1
  fi
fi

# SSH nie może być włączony (MASTER §8)
if grep -rql 'services\.openssh\.enable\s*=\s*true' "$REPO_DIR"/*.nix 2>/dev/null; then
  err "services.openssh.enable = true znalezione (MASTER §8 – serwer SSH musi być wyłączony)"
  SEC_ERR=1
fi

# Firewall nie może być wyłączony (MASTER §8)
if grep -rql 'networking\.firewall\.enable\s*=\s*false' "$REPO_DIR"/*.nix 2>/dev/null; then
  err "networking.firewall.enable = false znalezione (MASTER §8 – firewall musi być włączony)"
  SEC_ERR=1
fi

[[ "$SEC_ERR" -eq 1 ]] && exit 1
ok "Bezpieczeństwo OK"

# --- 4. Sprawdzenie BROKEN.md ---
section "BROKEN.md"
if [[ -f "$REPO_DIR/BROKEN.md" ]]; then
  BLOCKED_COUNT=$(grep -c "^### " "$REPO_DIR/BROKEN.md" 2>/dev/null || echo 0)
  warn "BROKEN.md ma $BLOCKED_COUNT wpisów – sprawdź przed dodaniem nowych pakietów"
else
  warn "Brak BROKEN.md w repo"
fi

# --- 5. Rozmiar repo ---
section "Rozmiar repo"
REPO_SIZE_MB=$(du -sm "$REPO_DIR" 2>/dev/null | awk '{print $1}' || echo 0)
GIT_SIZE_MB=$(du -sm "$REPO_DIR/.git" 2>/dev/null | awk '{print $1}' || echo 0)
echo "  Łączny rozmiar repo: ${REPO_SIZE_MB} MB (w tym .git: ${GIT_SIZE_MB} MB)"
if [[ "$REPO_SIZE_MB" -gt 3000 ]]; then
  err "Rozmiar repo przekracza 3 GB (${REPO_SIZE_MB} MB) – commit zablokowany (MASTER §9)"
  exit 1
elif [[ "$REPO_SIZE_MB" -gt 2500 ]]; then
  warn "Rozmiar repo zbliża się do limitu 3 GB (${REPO_SIZE_MB} MB)"
else
  ok "Rozmiar repo w normie"
fi

# --- 6. Dry-run ---
if [[ "$DRY" -eq 1 ]]; then
  section "Dry-build"
  echo "Podgląd co zostanie pobrane/skompilowane (bez zmian w systemie):"
  sudo nixos-rebuild dry-build -I nixos-config="$ENTRY" 2>&1 || true
  ok "Dry-build zakończony. Bez zmian w systemie i repo."
  exit 0
fi

# --- 7. Turbo off dla full na X250 (MASTER §5/§20) ---
OLD_TURBO=""
TURBO_ACTIVE=0
if [[ "$PROFILE" == "full" && -f "$TURBO_FILE" ]]; then
  if [[ -w "$NO_TURBO" ]]; then
    OLD_TURBO=$(cat "$NO_TURBO")
    # Przywróć poprzedni stan turbo ZAWSZE (też po błędzie / Ctrl+C)
    trap 'echo "$OLD_TURBO" > "$NO_TURBO"; echo -e "${YELLOW}Turbo procesora przywrócone (stan: $OLD_TURBO).${RESET}"' EXIT INT TERM
    echo 1 > "$NO_TURBO"
    TURBO_ACTIVE=1
    warn "Turbo procesora wyłączone na czas buildu full (X250 – MASTER §20)"
  else
    warn "TURBO_OFF_BUILD ustawiony, ale $NO_TURBO niedostępny (może nie być intel_pstate – AMD?). Budujemy dalej."
  fi
fi

# --- 8. Build (tryb: boot) ---
section "Build (tryb: boot)"

# Znajdź nixpkgs z kanałów root'a (sudo) – kanały użytkownika mogą wskazywać na unstable
# Kolejność: /nix/var/nix/profiles/per-user/root/channels/nixos → sudo nix-instantiate
NIXPKGS_PATH=""
ROOT_CHANNEL="/nix/var/nix/profiles/per-user/root/channels/nixos"
if [[ -d "$ROOT_CHANNEL" ]]; then
  NIXPKGS_PATH="$ROOT_CHANNEL"
else
  NIXPKGS_PATH=$(sudo nix-instantiate --find-file nixpkgs 2>/dev/null || true)
fi
if [[ -z "$NIXPKGS_PATH" ]]; then
  err "Nie można znaleźć nixpkgs. Sprawdź: sudo nix-channel --list"
  exit 1
fi

# nixos-rebuild-ng (Python, NixOS 26.05+) nie obsługuje --file z modułami NixOS –
# szuka konfiguracji w /etc/nixos/configuration.nix (lub flake.nix / system.nix).
# Dlatego kopiujemy config do /etc/nixos/ PRZED buildem. Commit robimy tylko po sukcesie.
# Jeśli build się wysypie, /etc/nixos/ ma nowe pliki, ale git jest czysty – bezpieczne.
section "Kopiowanie konfiguracji do $NIXOS_DIR (przed buildem)"
sudo rsync -a \
  --exclude=".git/" \
  --exclude="hardware-configuration.nix" \
  "$REPO_DIR/" "$NIXOS_DIR/"
ok "Konfiguracja skopiowana do $NIXOS_DIR"

# Symlink active-configuration.nix → właściwy plik wejściowy dla bieżącego profilu.
# nixos-rebuild switch (bez flag) czyta nixos-config z /etc/nix/nix.conf (nix.nixPath),
# który wskazuje właśnie na ten symlink – poprawny plik niezależnie od profilu i lokalizacji repo.
CONFIG_NAME="$(basename "$ENTRY")"
sudo ln -sf "$NIXOS_DIR/$CONFIG_NAME" "$NIXOS_DIR/active-configuration.nix"
ok "active-configuration.nix → $CONFIG_NAME"

# nixos-rebuild-ng (Python, NixOS 26.05+) traktuje configuration.nix jako wyrażenie nix,
# nie jako moduł – nie może go zewaluować bez systemu modułów, spada do system.nix.
# Rozwiązanie: pomijamy nixos-rebuild i używamy klasycznego nix-build '<nixpkgs/nixos>'
# z jawnym -I nixos-config=... – tak działał nixos-rebuild-bash przez lata.
BUILD_LINK="/tmp/nixos-rebuild-$$"
echo "Komenda: nix-build '<nixpkgs/nixos>' -A config.system.build.toplevel -I nixos-config=$NIXOS_DIR/$CONFIG_NAME"
BUILD_OK=0

if sudo nix-build '<nixpkgs/nixos>' \
    -A config.system.build.toplevel \
    -I "nixpkgs=$NIXPKGS_PATH" \
    -I "nixos-config=$NIXOS_DIR/$CONFIG_NAME" \
    -o "$BUILD_LINK" 2>&1; then

  SYSTEM_PATH=$(readlink -f "$BUILD_LINK")
  sudo rm -f "$BUILD_LINK"

  # Zarejestruj jako nową generację systemu
  sudo nix-env --profile /nix/var/nix/profiles/system --set "$SYSTEM_PATH"

  # Zainstaluj bootloader i zaktualizuj grub.cfg
  sudo "$SYSTEM_PATH/bin/switch-to-configuration" boot

  BUILD_OK=1
else
  sudo rm -f "$BUILD_LINK" 2>/dev/null || true
  err "nix-build nie powiodło się"
fi

# Wyłącz trap turbo przed normalnym zakończeniem (trap EXIT wykona się sam)
if [[ "$TURBO_ACTIVE" -eq 1 ]]; then
  trap - EXIT INT TERM
  echo "$OLD_TURBO" > "$NO_TURBO"
  ok "Turbo procesora przywrócone (stan: $OLD_TURBO)"
fi

if [[ "$BUILD_OK" -eq 0 ]]; then
  err "Build zakończony błędem. Nic nie commitowano, nic nie skopiowano."
  err "Poprzednia generacja dostępna w menu GRUB przy restarcie."
  exit 1
fi

ok "Build zakończony sukcesem"

# --- 9. Commit ---
section "Commit"
cd "$REPO_DIR"
if git diff --cached --quiet && git diff --quiet; then
  warn "Brak zmian do commitowania (working tree czysty)"
else
  git add -A
  git commit -m "$COMMIT_MSG"
  ok "Commit: $COMMIT_MSG"
fi

# --- 10. Zmiana profilu (--full) ---
if [[ "$FORCE_FULL" -eq 1 ]]; then
  echo "full" | sudo tee "$PROFILE_FILE" > /dev/null
  ok "PROFILE zmieniony na 'full'"
fi

# --- Podsumowanie ---
echo ""
echo -e "${GREEN}================================================${RESET}"
echo -e "${GREEN}  Sukces! Następne kroki:${RESET}"
echo -e "${GREEN}  1. Uruchom ponownie: systemctl reboot${RESET}"
echo -e "${GREEN}  2. Nowa generacja załaduje się przy starcie.${RESET}"
echo -e "${GREEN}  3. Jeśli coś nie działa: wybierz poprzednią generację w GRUB.${RESET}"
echo -e "${GREEN}================================================${RESET}"
