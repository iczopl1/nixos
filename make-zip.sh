#!/usr/bin/env bash
# make-zip.sh – zip rdzenia konfiguracji do wysłania na Discord / komuś
#
# Zasada (MASTER.md §9):
#   - zip zawiera TYLKO rdzeń: pliki tekstowe (.nix, .sh, .md, .patch, .toml, .lock, .qml, .rs itd.)
#   - wyklucza: vendor/ (snapshoty nvim), .git/, hardware-configuration.nix (per-maszyna)
#   - wynikowy zip musi mieścić się w limicie Discorda (20 MB dla darmowego konta)
#
# Użycie:
#   ./make-zip.sh               – tworzy nixos-config-<data>.zip w katalogu repo
#   ./make-zip.sh /ścieżka.zip  – podaj własną ścieżkę wyjściową

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE=$(date +%Y-%m-%d)
OUTPUT="${1:-$REPO_DIR/nixos-config-$DATE.zip}"
DISCORD_LIMIT_MB=20

echo "Tworzenie zipa rdzenia konfiguracji..."
echo "  Repo   : $REPO_DIR"
echo "  Wynik  : $OUTPUT"

# Sprawdź czy jesteśmy w repo git
if ! git -C "$REPO_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  echo "BŁĄD: $REPO_DIR nie jest repozytorium git." >&2
  exit 1
fi

# Usuń stary plik jeśli istnieje
rm -f "$OUTPUT"

# Użyj git archive – pakuje tylko pliki śledzone przez git (nie vendor/, nie .git/)
# hardware-configuration.nix jest w .gitignore lub można go wykluczyć explicite
git -C "$REPO_DIR" archive \
  --format=zip \
  --output="$OUTPUT" \
  --prefix="" \
  HEAD \
  -- \
  ':!hardware-configuration.nix' \
  ':!vendor/'

# Sprawdź rozmiar
SIZE_KB=$(du -sk "$OUTPUT" | awk '{print $1}')
SIZE_MB=$(awk "BEGIN {printf \"%.1f\", $SIZE_KB / 1024}")

echo "  Rozmiar: ${SIZE_MB} MB (${SIZE_KB} KB)"

if [[ "$SIZE_KB" -gt $((DISCORD_LIMIT_MB * 1024)) ]]; then
  echo "UWAGA: Zip przekracza limit Discorda ${DISCORD_LIMIT_MB} MB!" >&2
  echo "       Sprawdź czy nie ma dużych binarek w repo (vendor/, duże obrazy)." >&2
  echo "       Zip zapisany, ale może nie przejść na Discord." >&2
else
  echo "OK: Mieści się w limicie Discorda (${DISCORD_LIMIT_MB} MB)."
fi

echo "Gotowe: $OUTPUT"
