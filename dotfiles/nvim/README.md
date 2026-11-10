Moja konfiguracja Neovim – samodzielna (bez NvChada), na lazy.nvim.
LSP, formatery i debuggery są instalowane przez NixOS, nie przez Masona.
Opis skrótów i wtyczek: `doc/nvim.md` w repo konfiguracji.

Struktura:
- `init.lua` – lider + ładowanie `lua/config/*`
- `lua/config/` – opcje, skróty, autocmd, start lazy.nvim, funkcje pomocnicze
- `lua/plugins/` – jeden plik = jeden temat (ui, edytor, lsp, uzupełnianie, formatowanie, debugger, LaTeX, Markdown)
