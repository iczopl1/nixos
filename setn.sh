#!/usr/bin/env bash
# setn.sh – interaktywny skrypt post-install.
# T3.2: konfiguracja Tailscale, Syncthing, klucz SSH, ustawienia po stawianiu systemu.
# Uruchom: ./setn.sh
set -euo pipefail

NIXOS_DIR="/etc/nixos"
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
ask()   { printf "\033[33m%s\033[0m " "$*"; }

bold "=== setn – konfiguracja po instalacji ==="
echo ""

# --- 1. Tailscale ---
bold "1. Tailscale"
if systemctl is-active tailscaled &>/dev/null; then
  STATUS=$(tailscale status 2>/dev/null | head -1 || echo "")
  if echo "$STATUS" | grep -q "Logged in"; then
    green "  Tailscale: zalogowany – $STATUS"
  else
    ask "  Zalogować się do Tailscale? [t/N]"
    read -r ANS
    [[ "${ANS,,}" == "t" ]] && sudo tailscale up
  fi
else
  echo "  tailscaled nie działa – pomijam."
fi

echo ""

# --- 2. SSH klucz ---
bold "2. SSH klucz"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
  green "  Klucz istnieje: $SSH_KEY"
  echo "  Klucz publiczny:"
  cat "${SSH_KEY}.pub" 2>/dev/null
else
  ask "  Wygenerować nowy klucz ed25519? [t/N]"
  read -r ANS
  if [[ "${ANS,,}" == "t" ]]; then
    ask "  E-mail dla klucza:"
    read -r EMAIL
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "${EMAIL:-iczo@$(hostname)}" -f "$SSH_KEY"
    green "  Klucz wygenerowany."
    echo ""
    echo "  Klucz publiczny (skopiuj na serwery):"
    cat "${SSH_KEY}.pub"
  fi
fi

echo ""

# --- 3. Syncthing ---
bold "3. Syncthing"
if systemctl is-active syncthing &>/dev/null 2>&1 || \
   systemctl --user is-active syncthing &>/dev/null 2>&1; then
  green "  Syncthing działa."
  echo "  Panel: http://localhost:8384"
else
  echo "  Syncthing nie działa – sprawdź 'systemctl status syncthing'."
fi

echo ""

# --- 4. KeePassXC – baza haseł ---
bold "4. KeePassXC"
ask "  Podaj ścieżkę do bazy haseł (Enter = pomiń):"
read -r KPDB
if [[ -n "$KPDB" && -f "$KPDB" ]]; then
  green "  Baza: $KPDB"
  echo "  Uruchom: keepassxc \"$KPDB\""
elif [[ -n "$KPDB" ]]; then
  echo "  Plik nie istnieje: $KPDB"
fi

echo ""

# --- 5. Profil NixOS ---
bold "5. Profil NixOS"
if [[ -f "$NIXOS_DIR/PROFILE" ]]; then
  PROF=$(cat "$NIXOS_DIR/PROFILE")
  green "  Aktualny profil: $PROF"
  ask "  Zmienić na full (wymaga ./rebuild.sh --full)? [t/N]"
  read -r ANS
  if [[ "${ANS,,}" == "t" && "$PROF" == "minimal" ]]; then
    echo "  Uruchom: ./rebuild.sh --full \"przejście na full\""
  fi
else
  echo "  Brak $NIXOS_DIR/PROFILE – uruchom ./auto.sh"
fi

echo ""

# --- 6. TURBO_OFF_BUILD (ThinkPad X250 / starszy sprzęt) ---
bold "6. Turbo off podczas buildu full (ThinkPad X250 / starszy sprzęt)"
TURBO_FLAG="$NIXOS_DIR/TURBO_OFF_BUILD"
CPU=$(grep -m1 "model name" /proc/cpuinfo | sed 's/.*: //')
echo "  CPU: $CPU"
if [[ -f "$TURBO_FLAG" ]]; then
  green "  TURBO_OFF_BUILD aktywny."
else
  ask "  Włączyć wyłączanie turbo podczas buildu full? [t/N]"
  read -r ANS
  [[ "${ANS,,}" == "t" ]] && sudo touch "$TURBO_FLAG" && green "  Ustawiono."
fi

echo ""
bold "=== setn zakończony ==="
