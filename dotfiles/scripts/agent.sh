#!/usr/bin/env bash
# agent.sh – informacje dla AI agentów (Claude Code, itp.)
# Uruchom: agent  lub  source agent.sh
# Wypisuje: zainstalowane narzędzia, wersje, środowisko Python/LaTeX/nvim

echo "=== SYSTEM ==="
uname -srm
nixos-version 2>/dev/null || grep -m1 'ID\|VERSION' /etc/os-release

echo ""
echo "=== SHELL / PATH ==="
echo "Shell: $SHELL"
echo "Home:  $HOME"
echo "CWD:   $PWD"

echo ""
echo "=== NARZĘDZIA DEWELOPERSKIE ==="
for cmd in git gcc g++ clang cmake make ninja python3 node npm go rustc java; do
  if command -v "$cmd" &>/dev/null; then
    ver=$("$cmd" --version 2>&1 | head -1)
    printf "  %-12s %s\n" "$cmd" "$ver"
  fi
done

echo ""
echo "=== PYTHON ==="
python3 --version 2>/dev/null
python3 -c "import sys; print('  prefix:', sys.prefix)"
if [[ -n "$VIRTUAL_ENV" ]]; then
  echo "  venv: $VIRTUAL_ENV"
fi
python3 -c "
import importlib, sys
mods = ['numpy','scipy','cv2','torch','casadi','rclpy']
for m in mods:
    try:
        mod = importlib.import_module(m)
        ver = getattr(mod, '__version__', '?')
        print(f'  {m}: {ver}')
    except ImportError:
        pass
" 2>/dev/null

echo ""
echo "=== EDYTORY / AI ==="
nvim --version 2>/dev/null | head -1
claude --version 2>/dev/null || echo "  claude: nie znaleziono"

echo ""
echo "=== LATEX ==="
if command -v latexmk &>/dev/null; then
  latexmk --version 2>&1 | head -1
  pdflatex --version 2>&1 | head -1
else
  echo "  LaTeX: nie zainstalowany (texliveFull w profilu full)"
fi

echo ""
echo "=== NIX ==="
nix --version 2>/dev/null
echo "  NIXPKGS_PATH: $(nix-instantiate --find-file nixpkgs 2>/dev/null || echo 'nie znaleziono')"
[[ -f /etc/nixos/PROFILE ]] && echo "  NixOS profil: $(cat /etc/nixos/PROFILE)"

echo ""
echo "=== SERWISY (lokalne) ==="
systemctl --user is-active syncthing 2>/dev/null | xargs echo "  syncthing:"
echo "  syncthing UI: http://localhost:8384"
