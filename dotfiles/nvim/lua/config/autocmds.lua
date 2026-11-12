local util = require("config.util")
local group = vim.api.nvim_create_augroup("user_config", { clear = true })

---------------------------------------------------------------------------
-- `nvim <folder>` (np. `nvim .`):
--   bufor 1 = pusty - pierwszy otwarty plik (drzewo, Telescope, :e) zajmie jego miejsce,
--   bufor 2 = terminal w tym folderze (czeka w tle, Tab żeby przejść),
--   z boku drzewo plików.
-- `nvim plik` i samo `nvim` działają normalnie.
---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  nested = true,
  callback = function()
    if vim.fn.argc() ~= 1 then
      return
    end
    local dir = vim.fn.argv(0)
    if vim.fn.isdirectory(dir) ~= 1 then
      return
    end

    vim.cmd.cd(vim.fn.fnameescape(dir))
    local dir_buf = vim.api.nvim_get_current_buf()

    -- 1: pusty bufor
    local empty = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(empty)
    if vim.api.nvim_buf_is_valid(dir_buf) and dir_buf ~= empty then
      vim.api.nvim_buf_delete(dir_buf, { force = true })
    end

    -- 2: terminal (w tle)
    util.new_terminal_buffer({ focus = false })

    -- Drzewo plików z boku, kursor zostaje w pustym buforze.
    -- (Nie chcesz drzewa na starcie? Usuń te dwie linie.)
    vim.cmd("NvimTreeOpen")
    vim.cmd.wincmd("p")

    -- Gdy otworzysz pierwszy plik, a pusty bufor zostanie w tle - usuń go,
    -- żeby w pasku zostały: plik + terminal.
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = group,
      callback = function()
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(empty) then
            return
          end
          -- Neovim mógł użyć pustego bufora dla pliku (ma już nazwę) - nic do zrobienia.
          if vim.api.nvim_buf_get_name(empty) ~= "" then
            return
          end
          local is_blank = not vim.bo[empty].modified
            and vim.api.nvim_buf_line_count(empty) == 1
            and vim.api.nvim_buf_get_lines(empty, 0, 1, false)[1] == ""
          if is_blank and #vim.fn.win_findbuf(empty) == 0 then
            vim.api.nvim_buf_delete(empty, {})
          end
        end)
        return true -- jednorazowo
      end,
    })
  end,
})

---------------------------------------------------------------------------
-- Krótkie podświetlenie tego, co zostało skopiowane (y)
---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.hl.on_yank({ timeout = 200 })
  end,
})

---------------------------------------------------------------------------
-- Terminal: bez numerów linii, od razu tryb wpisywania po wejściu
---------------------------------------------------------------------------
vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter" }, {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "terminal" then
      return
    end
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
  end,
})
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = group,
  pattern = "term://*",
  callback = function()
    vim.cmd.startinsert()
  end,
})

-- T3.5: animacja prędkości pisania (CursorLine + lualine WPM)
require("config.typing_speed").setup()

-- LaTeX: plik *.latexmain (np. main.tex.latexmain) vimtex wykrywa sam.
