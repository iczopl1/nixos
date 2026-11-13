# Neovim

Samodzielna konfiguracja (bez NvChada) na **lazy.nvim**. Wymaga Neovim ≥ 0.11 (NixOS 25.11).

- Konfiguracja: `dotfiles/nvim/` → link `~/.config/nvim` (z `dotfiles.nix`).
- Wtyczki pobiera lazy.nvim przy pierwszym starcie (potrzebny internet i `git`); wersje zapisuje w `lazy-lock.json`.
- **LSP, formatery i debuggery instaluje NixOS** (`programs.nix`, `python.nix`) – Masona nie ma.
- Motyw: catppuccin (mocha), jak wcześniej.

## Struktura

| Plik | Co ustawia |
|---|---|
| `init.lua` | lider = Spacja, ładuje `lua/config/*` |
| `lua/config/options.lua` | opcje: schowek systemowy, wcięcia 2 spacje, numery, mysz wyłączona… |
| `lua/config/keymaps.lua` | **wszystkie skróty** (poza LSP i debuggerem) |
| `lua/config/autocmds.lua` | start `nvim <folder>`, podświetlenie kopiowania, zachowanie terminala |
| `lua/config/util.lua` | funkcje: nowy terminal w buforze, zamykanie buforów |
| `lua/config/terms.lua` | terminale wysuwane Alt+h/v/i |
| `lua/config/lazy.lua` | start lazy.nvim |
| `lua/plugins/ui.lua` | catppuccin, lualine (pasek stanu), bufferline (pasek buforów), which-key, linie wcięć |
| `lua/plugins/editor.lua` | telescope, nvim-tree, gitsigns, autopairs, toggleterm |
| `lua/plugins/treesitter.lua` | kolorowanie składni |
| `lua/plugins/lsp.lua` | serwery LSP + skróty LSP + venv dla Pythona |
| `lua/plugins/completion.lua` | uzupełnianie: **blink.cmp** + friendly-snippets |
| `lua/plugins/format.lua` | conform – formatowanie przy zapisie |
| `lua/plugins/dap.lua` | debugger (Python, C/C++, STM32) + skróty |
| `lua/plugins/latex.lua` | vimtex (zathura + latexmk) |
| `lua/plugins/markdown.lua` | glow (`:Glow`) |

## Start: `nvim .` (albo `nvim <folder>`)

1. Przechodzi do tego folderu (`:cd`).
2. Bufor **1 – pusty**: pierwszy otwarty plik (z drzewa, Telescope albo `:e plik`) zajmuje jego miejsce.
3. Bufor **2 – terminal** w tym folderze, czeka w tle (`Tab` żeby do niego przejść).
4. Z boku otwiera się drzewo plików, kursor zostaje w pustym buforze.

`nvim plik` i samo `nvim` działają normalnie (bez terminala i drzewa).
Nie chcesz drzewa na starcie – usuń dwie linie `NvimTreeOpen` / `wincmd` w `autocmds.lua`.

## Schowek (y / p ↔ SUPER+V)

- `y`, `yy`, `d`, `p`, `P` działają na **schowku systemowym** (`clipboard=unnamedplus`, przez `wl-clipboard`).
- Wszystko skopiowane w nvim trafia do historii **SUPER+V** (cliphist, autostart w `mango-autostart.conf`).
- Wybrane z SUPER+V wklejasz w nvim zwykłym `p` (w trybie wpisywania i w terminalu: `Ctrl+Shift+V`).
- `x` i `c` **nie** nadpisują schowka (usuwanie znaków nie zaśmieca historii).
- `p` na zaznaczeniu wkleja i **zostawia** schowek (można wklejać wiele razy).
- Skopiowany tekst miga na chwilę.

## Skróty

Lider = **Spacja**. Spacja i chwila czekania pokazuje podpowiedzi (which-key), `<Space>wK` – wszystkie skróty.

### Twoje (ze starej konfiguracji)

| Skrót | Działanie |
|---|---|
| `;` | tryb komend (`:`) |
| `jk` (insert) | wyjście do normal |
| `PageUp` / `PageDown` | wyłączone |
| mysz | wyłączona |

### Bufory (pasek u góry)

| Skrót | Działanie |
|---|---|
| `Tab` / `Shift+Tab` | następny / poprzedni bufor |
| `Alt+1` … `Alt+9` | bufor nr 1–9 (numery widać w pasku) |
| `<Space>bn` | nowy pusty bufor |
| `<Space>bt` | nowy bufor z terminalem |
| `<Space>x` | zamknij bufor (okno zostaje) |
| `<Space>bo` | zamknij pozostałe bufory (niezapisane zostają) |
| `<Space>bp` | wybierz bufor literą |
| `<Space>b<` / `<Space>b>` | przesuń bufor w pasku |

### Karty (osobne układy okien)

| Skrót | Działanie |
|---|---|
| `<Space>tn` | nowa karta |
| `<Space>tc` | zamknij kartę |
| `Alt+l` / `Alt+j` | następna / poprzednia karta (także wbudowane `gt` / `gT`) |

### Terminal

| Skrót | Działanie |
|---|---|
| `Esc Esc` | z terminala do trybu normal (potem `Tab` = inny bufor) |
| `Ctrl+h/j/k/l` | przejście do okna obok (też z terminala) |
| `Alt+h` / `Alt+v` / `Alt+i` | terminal wysuwany: poziomy / pionowy / pływający (drugi raz chowa) |
| `<Space>bt` | terminal jako zwykły bufor |

Wejście do bufora z terminalem od razu włącza tryb wpisywania.

### Pliki i szukanie

| Skrót | Działanie |
|---|---|
| `Ctrl+n` | drzewo plików on/off |
| `<Space>e` | przejdź do drzewa |
| `<Space>ff` | szukaj plików |
| `<Space>fa` | szukaj wszystkich plików (też ukrytych / ignorowanych) |
| `<Space>fw` | szukaj tekstu w projekcie |
| `<Space>fb` | lista buforów |
| `<Space>fo` | ostatnie pliki |
| `<Space>fz` | szukaj w bieżącym pliku |
| `<Space>fh` | pomoc |
| `<Space>cm` / `<Space>gt` | git: commity / status |
| `<Space>th` | wybór motywu (z podglądem) |

### Edycja

| Skrót | Działanie |
|---|---|
| `Ctrl+s` | zapisz |
| `Ctrl+c` | skopiuj cały plik |
| `<Space>/` | komentarz (linia / zaznaczenie) |
| `<Space>fm` | formatuj |
| `Esc` | wyczyść podświetlenie wyszukiwania |
| `<Space>n` / `<Space>rn` | numery linii / numery względne |
| `Ctrl+h/j/k/l` | przejście między oknami |

### Uzupełnianie (blink.cmp)

| Klawisz | Działanie |
|---|---|
| `Enter` | zatwierdź podpowiedź |
| `Tab` / `Shift+Tab` | następna / poprzednia podpowiedź, skok w snippecie |
| `Ctrl+Space` | pokaż podpowiedzi / dokumentację |
| `Ctrl+e` | schowaj |

### LSP (gdy serwer działa dla pliku)

| Skrót | Działanie |
|---|---|
| `gd` / `gD` / `gi` | definicja / deklaracja / implementacja |
| `gr` | użycia (Telescope) |
| `K` | opis pod kursorem |
| `<Space>ra` | zmień nazwę |
| `<Space>ca` | akcje kodu |
| `<Space>D` | definicja typu |
| `<Space>sh` | sygnatura funkcji |
| `<Space>ds` | lista błędów / ostrzeżeń |
| `<Space>wa` / `wr` / `wl` | foldery robocze: dodaj / usuń / pokaż |

### Debugger

| Skrót | Działanie |
|---|---|
| `<Space>db` | breakpoint on/off |
| `<Space>dr` | start / kontynuuj |
| `<Space>do` / `<Space>di` / `<Space>dO` | krok nad / do środka / wyjdź |
| `<Space>dq` | zakończ |
| `<Space>du` | panel debuggera on/off (otwiera się sam przy starcie) |

### LaTeX (vimtex, w plikach .tex)

| Skrót | Działanie |
|---|---|
| `<Space>ll` | kompilacja ciągła (latexmk) |
| `<Space>lv` | podgląd PDF (zathura) |
| `<Space>le` | lista błędów |
| `<Space>lc` | usuń pliki pomocnicze |

## Języki

| Język | LSP | Formater (przy zapisie) | Debugger |
|---|---|---|---|
| Lua | lua-language-server | stylua | – |
| Python | pyright (z venv projektu) | black | debugpy (`python3`) |
| C / C++ | clangd (`--query-driver` dla cross-kompilatorów) | clang-format | lldb-dap; STM32: `gdb` (host, multiarch) + st-util |
| Java | java-language-server | google-java-format | – |
| LaTeX | texlab | – | – |

Wszystko z NixOS: `lua-language-server`, `stylua`, `google-java-format`, `java-language-server`, `zathura`, `glow` (`programs.nix`),
`clang-tools`, `lldb`, `texlab`, `texliveFull` (`programs.nix`), `pyright`, `black`, `debugpy` (`python.nix`).

### Python i venv

Pyright szuka interpretera: aktywny `$VIRTUAL_ENV` → `.venv/` → `venv/` w katalogu projektu.
Znaleziony venv jest „aktywowany” w nvim (jego `bin` trafia do `PATH`), więc importy z venv działają w podpowiedziach.

### Kolorowanie składni (treesitter)

Parsery kompilują się przy pierwszym uruchomieniu (`gcc`): lua, vim, python, c, cpp, java, kotlin, go, bash, nix, json, yaml, toml, markdown, html, css, javascript.
Aktualizacja: `:TSUpdate`.

## Zmiany względem NvChada

| Było (NvChad) | Jest |
|---|---|
| base46 catppuccin | `catppuccin/nvim` |
| pasek stanu NvChad | lualine |
| tabufline | bufferline (numery buforów, Alt+1…9) |
| nvim-cmp + LuaSnip | blink.cmp + friendly-snippets |
| Mason (pyright, clangd, black, debugpy, codelldb…) | pakiety NixOS |
| codelldb | lldb-dap |
| terminale NvChad (Alt+h/v/i) | toggleterm (te same skróty) |
| wybór motywu NvChad | Telescope colorscheme |
| volt, menu, minty, none-ls | usunięte |
| vimtex + latexrun (nieinstalowany) | vimtex + latexmk (z texliveFull) |
| konfiguracja STM32 z nieistniejącym typem `cdbg` | gdb w trybie DAP (patrz niżej) |

## Uwagi

- **STM32:** konfiguracja „STM32: make debug + st-util (ST-Link)” sama odpala `make debug` w katalogu projektu
  (konwencja Makefile – patrz `agent` w terminalu), szuka `.elf` w `build/debug/` i startuje `st-util` (stlink, :4242).
  Adapter to `gdb` (host, multiarch, ma Python) – **nie** `arm-none-eabi-gdb` z `gcc-arm-embedded`, bo ten jest
  budowany `--without-python` i `--interpreter=dap` się w nim nie odpala.
- **lazy-lock.json** musi być zapisywalny – jeśli konfiguracja leży w `/etc/nixos` (root), lazy nie zapisze wersji wtyczek.
- **blink.cmp** pobiera gotowy moduł dopasowywania (Rust); jeśli się nie uda, działa wolniejsza wersja w Lua z ostrzeżeniem.
- Pierwsze uruchomienie: `:Lazy` pokazuje instalację wtyczek, `:checkhealth` – brakujące programy.
