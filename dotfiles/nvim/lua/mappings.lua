require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set
map({"","i","v"},"<mouse>",'<Nop>',{noremap = true,silent=true})
map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map({'','i'}, '<PageUp>', '<Nop>', { noremap = true, silent = true })
map({'','i'}, '<PageDown>', '<Nop>', { noremap = true, silent = true })
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
