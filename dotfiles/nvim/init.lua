-- Neovim bez NvChada. Wymaga Neovim >= 0.11 (NixOS 25.11).
-- Wtyczki: lazy.nvim (lua/plugins/*.lua). Serwery LSP, formatery i debuggery
-- pochodzą z NixOS (programs.nix / python.nix) - bez Masona.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.lazy")
require("config.keymaps")
require("config.autocmds")
