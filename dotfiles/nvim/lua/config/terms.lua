-- Trzy terminale wysuwane (toggleterm): poziomy, pionowy, pływający.
-- Każdy pamięta swoją sesję między otwarciami.
local M = {}
local terms = {}

local ids = { horizontal = 101, vertical = 102, float = 103 }

function M.toggle(direction)
  if not terms[direction] then
    local Terminal = require("toggleterm.terminal").Terminal
    terms[direction] = Terminal:new({
      direction = direction,
      count = ids[direction],
      hidden = true, -- nie pokazuj w liście buforów
    })
  end
  terms[direction]:toggle()
end

return M
