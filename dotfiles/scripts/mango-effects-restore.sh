#!/usr/bin/env bash
# mango-effects-restore.sh – przywraca blur/shadows/animations/layer_animations zapisane
# przez `effects` (effects-ctl.sh) w poprzedniej sesji.
#
# Powód: ~/.config/mango/config.conf to symlink (L+ w dotfiles.nix) wprost do repo – przy
# KAŻDYM starcie mango wraca do wartości wpisanych na stałe w repo, niezależnie od tego, co
# user ustawił przez `effects` ostatnio. Rzeczywisty stan jest w ~/.config/mango-effects
# (effects-ctl.sh go tam zapisuje przy każdej zmianie) – ten skrypt go stosuje przez
# `mmsg dispatch setoption,...` zaraz po starcie mango (exec_once, pierwsza linia).
set -euo pipefail

STATE="$HOME/.config/mango-effects"
[ -f "$STATE" ] || exit 0

# mmsg może nie odpowiadać przez pierwsze ułamki sekundy po starcie mango – czekaj do ~5 s.
for _ in $(seq 1 25); do
  mmsg get cursorpos >/dev/null 2>&1 && break
  sleep 0.2
done

while IFS='=' read -r key val; do
  [ -n "$key" ] && [ -n "$val" ] || continue
  mmsg dispatch "setoption,$key,$val" >/dev/null 2>&1 || true
done < "$STATE"
