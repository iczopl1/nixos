-- Wszystkie skróty w jednym miejscu. Lider = Spacja.
-- Skróty LSP są w lua/plugins/lsp.lua (działają tylko gdy LSP jest podłączony),
-- debuggera w lua/plugins/dap.lua.
local map = vim.keymap.set
local util = require("config.util")

---------------------------------------------------------------------------
-- Twoje skróty (ze starej konfiguracji)
---------------------------------------------------------------------------
map("n", ";", ":", { desc = "Tryb komend" })
map("i", "jk", "<Esc>", { desc = "Wyjście z trybu wpisywania" })
map({ "", "i" }, "<PageUp>", "<Nop>")
map({ "", "i" }, "<PageDown>", "<Nop>")

---------------------------------------------------------------------------
-- Ogólne (jak w NvChad)
---------------------------------------------------------------------------
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Wyczyść podświetlenie wyszukiwania" })
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<CR>", { desc = "Zapisz" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "Skopiuj cały plik" })
map("n", "<leader>n", "<cmd>set number!<CR>", { desc = "Numery linii on/off" })
map("n", "<leader>rn", "<cmd>set relativenumber!<CR>", { desc = "Względne numery on/off" })

-- Okna
map("n", "<C-h>", "<C-w>h", { desc = "Okno w lewo" })
map("n", "<C-j>", "<C-w>j", { desc = "Okno w dół" })
map("n", "<C-k>", "<C-w>k", { desc = "Okno w górę" })
map("n", "<C-l>", "<C-w>l", { desc = "Okno w prawo" })

-- Komentarze (wbudowane gc w Neovim)
map("n", "<leader>/", "gcc", { remap = true, desc = "Komentarz linii" })
map("v", "<leader>/", "gc", { remap = true, desc = "Komentarz zaznaczenia" })

---------------------------------------------------------------------------
-- Schowek systemowy
-- y / yy / p / P działają na schowku systemowym (opcja clipboard=unnamedplus),
-- więc to, co skopiujesz, jest w historii SUPER+V, a wybrane z SUPER+V wkleja `p`.
-- `x` i `c` nie nadpisują schowka (żeby usuwanie znaków nie zaśmiecało historii).
---------------------------------------------------------------------------
map({ "n", "v" }, "x", '"_x', { desc = "Usuń znak (bez kopiowania)" })
map({ "n", "v" }, "c", '"_c', { desc = "Zmień (bez kopiowania)" })
map("v", "p", '"_dP', { desc = "Wklej na zaznaczenie (schowek zostaje)" })
-- W trybie wpisywania i w terminalu wkleja Ctrl+Shift+V terminala (alacritty).

---------------------------------------------------------------------------
-- Bufory (pasek u góry = bufferline)
---------------------------------------------------------------------------
map("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "Następny bufor" })
map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Poprzedni bufor" })
for i = 1, 9 do
  map("n", "<A-" .. i .. ">", "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", { desc = "Bufor " .. i })
end
map("n", "<leader>x", function() util.close_buffer() end, { desc = "Zamknij bufor" })
map("n", "<leader>bn", util.new_empty_buffer, { desc = "Nowy pusty bufor" })
map("n", "<leader>bt", function() util.new_terminal_buffer({ focus = true }) end, { desc = "Nowy bufor z terminalem" })
map("n", "<leader>bo", util.close_other_buffers, { desc = "Zamknij pozostałe bufory" })
map("n", "<leader>bp", "<cmd>BufferLinePick<CR>", { desc = "Wybierz bufor literą" })
map("n", "<leader>b<", "<cmd>BufferLineMovePrev<CR>", { desc = "Przesuń bufor w lewo" })
map("n", "<leader>b>", "<cmd>BufferLineMoveNext<CR>", { desc = "Przesuń bufor w prawo" })

---------------------------------------------------------------------------
-- Karty (tabpage - osobne układy okien)
---------------------------------------------------------------------------
map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Nowa karta" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Zamknij kartę" })
map("n", "<A-l>", "<cmd>tabnext<CR>", { desc = "Następna karta" })
map("n", "<A-j>", "<cmd>tabprevious<CR>", { desc = "Poprzednia karta" })

---------------------------------------------------------------------------
-- Terminal
---------------------------------------------------------------------------
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Terminal: tryb normal" })
map("t", "<C-h>", [[<C-\><C-n><C-w>h]], { desc = "Okno w lewo" })
map("t", "<C-j>", [[<C-\><C-n><C-w>j]], { desc = "Okno w dół" })
map("t", "<C-k>", [[<C-\><C-n><C-w>k]], { desc = "Okno w górę" })
map("t", "<C-l>", [[<C-\><C-n><C-w>l]], { desc = "Okno w prawo" })

-- Terminale wysuwane (toggleterm), jak Alt+h/v/i w NvChad
map({ "n", "t" }, "<A-h>", function() require("config.terms").toggle("horizontal") end, { desc = "Terminal poziomy" })
map({ "n", "t" }, "<A-v>", function() require("config.terms").toggle("vertical") end, { desc = "Terminal pionowy" })
map({ "n", "t" }, "<A-i>", function() require("config.terms").toggle("float") end, { desc = "Terminal pływający" })

---------------------------------------------------------------------------
-- Drzewo plików (nvim-tree)
---------------------------------------------------------------------------
map("n", "<C-n>", "<cmd>NvimTreeToggle<CR>", { desc = "Drzewo plików on/off" })
map("n", "<leader>e", "<cmd>NvimTreeFocus<CR>", { desc = "Przejdź do drzewa plików" })

---------------------------------------------------------------------------
-- Telescope (szukanie)
---------------------------------------------------------------------------
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Szukaj plików" })
map("n", "<leader>fa", "<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>", { desc = "Szukaj wszystkich plików" })
map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "Szukaj tekstu" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Lista buforów" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Pomoc" })
map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Ostatnie pliki" })
map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Szukaj w buforze" })
map("n", "<leader>cm", "<cmd>Telescope git_commits<CR>", { desc = "Git: commity" })
map("n", "<leader>gt", "<cmd>Telescope git_status<CR>", { desc = "Git: status" })
map("n", "<leader>th", "<cmd>Telescope colorscheme enable_preview=true<CR>", { desc = "Wybór motywu" })

---------------------------------------------------------------------------
-- Formatowanie, diagnostyka, which-key
---------------------------------------------------------------------------
map({ "n", "v" }, "<leader>fm", function()
  require("conform").format({ lsp_format = "fallback" })
end, { desc = "Formatuj" })
map("n", "<leader>ds", vim.diagnostic.setloclist, { desc = "Diagnostyka: lista" })
map("n", "<leader>wK", "<cmd>WhichKey<CR>", { desc = "Wszystkie skróty" })
