-- Start lazy.nvim (menedżer wtyczek). Przy pierwszym uruchomieniu pobiera się z GitHuba.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Nie udało się pobrać lazy.nvim:\n" .. out, "ErrorMsg" } }, true, {})
    return
  end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "plugins" } },
  defaults = { lazy = false },
  install = { colorscheme = { "catppuccin" } },
  checker = { enabled = false }, -- bez automatycznego sprawdzania aktualizacji
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
        "rplugin",
      },
    },
  },
})
