-- Animacja prędkości pisania (T3.5): zmienia kolor CursorLine i wyświetla WPM w lualine.
-- Zakres 1–90 WPM: zimny błękit → ciepły pomarańcz → czerwień.
-- Aktywna tylko w trybie wpisywania; CursorLine wraca do domyślnego po 2 s od wyjścia.
local M = {}

local timestamps = {}
local WINDOW_S    = 5    -- okno rolling (sekundy)
local CHARS_PER_WORD = 5

-- Zatrzymaj timer jeśli istnieje (uv.Timer)
local flush_timer = nil
local function cancel_timer()
  if flush_timer and not flush_timer:is_closing() then
    flush_timer:close()
  end
  flush_timer = nil
end

-- Wyczyść stare znaczniki i policz WPM
local function calc_wpm()
  local now = vim.uv.hrtime() / 1e9
  local cutoff = now - WINDOW_S
  local i = 1
  while i <= #timestamps and timestamps[i] < cutoff do i = i + 1 end
  if i > 1 then timestamps = vim.list_slice(timestamps, i) end
  if #timestamps < 2 then return 0 end
  local elapsed = now - timestamps[1]
  if elapsed < 0.1 then return 0 end
  return math.floor((#timestamps / CHARS_PER_WORD) / (elapsed / 60))
end

-- Gradient: {wpm_max, r, g, b} – każdy przedział interpoluje do kolejnego
local STOPS = {
  {  0, 0x1e, 0x1e, 0x2e },  -- spoczynek   – catppuccin base
  { 20, 0x14, 0x25, 0x4a },  -- wolno       – zimny błękit
  { 50, 0x2a, 0x1a, 0x06 },  -- średnio     – bursztyn
  { 90, 0x38, 0x06, 0x06 },  -- szybko      – czerwień
}

local function lerp(a, b, t)
  return math.floor(a + (b - a) * math.max(0, math.min(1, t)))
end

local function wpm_to_color(wpm)
  local s = STOPS
  for i = 2, #s do
    if wpm <= s[i][1] then
      local lo, hi = s[i-1], s[i]
      local t = (wpm - lo[1]) / math.max(hi[1] - lo[1], 1)
      return string.format("#%02x%02x%02x",
        lerp(lo[2], hi[2], t),
        lerp(lo[3], hi[3], t),
        lerp(lo[4], hi[4], t))
    end
  end
  local last = s[#s]
  return string.format("#%02x%02x%02x", last[2], last[3], last[4])
end

local WPM_FILE = "/tmp/nvim-wpm-" .. tostring(vim.uv.getuid())

local function apply_hl(wpm)
  local bg = wpm_to_color(wpm)
  vim.api.nvim_set_hl(0, "CursorLine", { bg = bg })
  -- Zapisz WPM dla wpm-border.sh (T3.13)
  local f = io.open(WPM_FILE, "w")
  if f then f:write(tostring(wpm)); f:close() end
end

local function restore_hl()
  timestamps = {}
  vim.api.nvim_set_hl(0, "CursorLine", {})  -- powrót do wartości colorscheme
  -- Usuń plik WPM żeby wpm-border.sh wiedział, że wyszliśmy z insert
  os.remove(WPM_FILE)
end

-- Publiczne: pobierz bieżące WPM (dla lualine)
function M.get_wpm()
  return calc_wpm()
end

-- Publiczne: kolor do wyświetlenia WPM w lualine
function M.wpm_fg(wpm)
  if wpm == 0 then return "#585b70" end       -- catppuccin surface2 – nieaktywny
  if wpm < 20  then return "#7dcfff" end      -- błękit
  if wpm < 50  then return "#ff9e64" end      -- pomarańcz
  return "#f7768e"                            -- czerwień
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("typing_speed", { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = grp,
    callback = function()
      table.insert(timestamps, vim.uv.hrtime() / 1e9)
      -- Odśwież highlight max raz na 200 ms
      cancel_timer()
      flush_timer = vim.uv.new_timer()
      flush_timer:start(200, 0, vim.schedule_wrap(function()
        cancel_timer()
        apply_hl(calc_wpm())
      end))
    end,
  })

  -- Wyjście z trybu wpisywania: przywróć CursorLine po 2 s
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = grp,
    callback = function()
      cancel_timer()
      vim.defer_fn(function()
        if vim.fn.mode() ~= "i" then restore_hl() end
      end, 2000)
    end,
  })
end

return M
