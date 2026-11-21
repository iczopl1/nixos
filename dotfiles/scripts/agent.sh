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

echo ""
echo "=== EMBEDDED (STM32 / ARM Cortex-M) ==="
for cmd in arm-none-eabi-gcc arm-none-eabi-gdb gdb openocd st-flash st-util bear; do
  if command -v "$cmd" &>/dev/null; then
    printf "  %-18s %s\n" "$cmd" "$("$cmd" --version 2>&1 | head -1)"
  fi
done
cat <<'MAKE_CONVENTION'

  Konwencja Makefile dla projektów STM32/ARM (ten sam styl we wszystkich
  projektach -> nvim LSP/DAP podłącza się bez osobnej konfiguracji per projekt):

    PROJECT := nazwa_projektu          # jedna zmienna, jedna nazwa .elf/.bin/.hex
    CC      := arm-none-eabi-gcc
    C_SOURCES := $(wildcard Core/Src/*.c) ...
    INCLUDES  := -ICore/Inc ...
    DEFINES   := -DUSE_HAL_DRIVER -DSTM32xxxx
    MCU_FLAGS := -mcpu=... -mthumb -mfpu=... -mfloat-abi=...

    Cele (dokładnie te nazwy - DAP w nvim i skrypty ich oczekują):
      all      - build release (-Os -g0), .elf+.bin+.hex          (= make)
      debug    - build debug (-Og -g3 -DDEBUG) do build/debug/*.elf
                 (nvim DAP: "STM32: make debug + st-util" odpala ten cel
                  i szuka build/debug/*.elf - NIE nazywaj inaczej niż "debug")
      push     - all + flash (st-flash write ... $(FLASH_ADDR))
      clean    - rm -rf build
      compiledb- `bear -- $(MAKE) debug`, regeneruje compile_commands.json
                 (odpalić po KAŻDYM dodaniu/usunięciu pliku .c - inaczej
                  clangd nie zobaczy nowych plików; fallback: .clangd w repo)
      print-%  - `@echo $($*)` - odpytanie zmiennej (np. `make print-PROJECT`)

    Osobny katalog per konfigurację (build/release/, build/debug/) - NIE jeden
    build/ ze wspólnymi .o dla obu, inaczej zmiana flag nie wymusza rekompilacji.

    Debugger: st-util (ze stlink, ten sam toolchain co `make push`), NIE OpenOCD
    - st-util nie potrzebuje plików .cfg per-chip, gdbserver na :4242.
    DAP adapter w nvim musi używać `gdb` (host, multiarch, --with-python),
    NIE `arm-none-eabi-gdb` - ten z gcc-arm-embedded jest --without-python,
    więc --interpreter=dap się nie uruchamia.

    LSP (clangd) wymaga w nvim: cmd z --query-driver=**/arm-none-eabi-*
    (bez tego clangd nie ufa cross-kompilatorowi i zgłasza fałszywe błędy
    "stddef.h not found" itp.) - to jest już w dotfiles/nvim/lua/plugins/lsp.lua,
    nowy projekt nie wymaga nic dodatkowego w tym miejscu.
MAKE_CONVENTION
