-- Opcje (przeniesione z domyślnych NvChada + Twoje).
local o = vim.opt

-- Schowek systemowy: y/d/p działają na schowku Waylanda (wl-copy/wl-paste).
-- Skopiowane w nvim trafia do historii SUPER+V (cliphist), a wybrane z SUPER+V
-- wklejasz w nvim zwykłym `p`.
o.clipboard = "unnamedplus"

o.mouse = "" -- mysz wyłączona (jak wcześniej)
o.laststatus = 3 -- jeden pasek stanu na dole
o.showmode = false
o.cursorline = true
o.cursorlineopt = "number"
o.termguicolors = true

-- Wcięcia
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true

o.fillchars = { eob = " " }
o.ignorecase = true
o.smartcase = true

-- Numery linii (T2.11): bieżąca linia = bezwzględna, reszta = relatywna (5,4,3,2,1,{nr},1,2,3,4,5)
o.number = true
o.relativenumber = true
o.numberwidth = 2
o.ruler = false

o.shortmess:append("sI") -- bez ekranu powitalnego
o.signcolumn = "yes"
o.splitbelow = true
o.splitright = true
o.timeoutlen = 400
o.undofile = true
o.updatetime = 250
o.whichwrap:append("<>[]hl")
o.hidden = true -- przełączanie buforów bez zapisywania (terminal zostaje w tle)

-- Wbudowane wtyczki, których nie używamy (netrw zastępuje nvim-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
