-- Pomocnicze funkcje: bufory, terminale, Python.
local M = {}

-- Znajdź działający venv Linuksa w folderze projektu (.venv, potem venv).
-- Waliduje, że bin/python NAPRAWDĘ istnieje – inaczej "venv/" zsynchronizowany
-- z Windows (venv/Scripts/python.exe) zostałby błędnie wzięty za linuksowy
-- (tak zepsuty był debugger: pythonPath wskazywał na nieistniejący plik).
-- Zwraca ścieżkę do folderu venv (nie do pliku python) albo nil.
function M.python_venv(root_dir)
  local candidates = {}
  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
    table.insert(candidates, vim.env.VIRTUAL_ENV)
  end
  if root_dir then
    table.insert(candidates, root_dir .. "/.venv")
    table.insert(candidates, root_dir .. "/venv")
  end
  for _, path in ipairs(candidates) do
    if vim.fn.executable(path .. "/bin/python") == 1 then
      return path
    end
  end
end

-- Nowy bufor z terminalem (powłoka w bieżącym katalogu).
-- opts.focus = true -> przełącz się na niego i wejdź w tryb wpisywania.
function M.new_terminal_buffer(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_call(buf, function()
    vim.fn.jobstart(vim.o.shell, { term = true })
  end)
  if opts.focus then
    vim.api.nvim_set_current_buf(buf)
    vim.cmd.startinsert()
  end
  return buf
end

-- Nowy pusty bufor w bieżącym oknie.
function M.new_empty_buffer()
  vim.cmd.enew()
end

-- Lista buforów widocznych w pasku (listed), bez podanego.
local function other_listed(buf)
  return vim.tbl_filter(function(b)
    return b ~= buf and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
  end, vim.api.nvim_list_bufs())
end

-- Zamknij bufor, ale zostaw okno (pokaż w nim inny bufor).
-- Terminal zamyka się bez pytania; plik z niezapisanymi zmianami - nie.
function M.close_buffer(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local is_term = vim.bo[buf].buftype == "terminal"
  if vim.bo[buf].modified and not is_term then
    vim.notify("Bufor ma niezapisane zmiany - zapisz (:w) albo :bd!", vim.log.levels.WARN)
    return
  end

  local others = other_listed(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      local alt = vim.fn.bufnr("#")
      if alt > 0 and alt ~= buf and vim.tbl_contains(others, alt) then
        vim.api.nvim_set_current_buf(alt)
      elseif #others > 0 then
        vim.api.nvim_set_current_buf(others[1])
      else
        vim.cmd.enew()
      end
    end)
  end

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = is_term })
  end
end

-- Zamknij wszystkie bufory oprócz bieżącego (pomija niezapisane).
function M.close_other_buffers()
  local cur = vim.api.nvim_get_current_buf()
  for _, b in ipairs(other_listed(cur)) do
    local is_term = vim.bo[b].buftype == "terminal"
    if is_term or not vim.bo[b].modified then
      vim.api.nvim_buf_delete(b, { force = is_term })
    end
  end
end

return M
