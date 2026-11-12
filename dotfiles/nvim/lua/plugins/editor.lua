-- Edytor: szukanie, drzewo plików, git, nawiasy, terminale, nawigacja, diagnostyka.
return {
  -- Surround: cs"' zmień, ys dodaj, ds usuń (np. ysiw" owija słowo cudzysłowem)
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  -- Flash: szybka nawigacja po ekranie – s/S wyszukuje i skacze jednym ruchem
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        search = { enabled = false }, -- nie zastępuje /
      },
    },
    keys = {
      { "s",     function() require("flash").jump() end,              mode = { "n", "x", "o" }, desc = "Flash: skocz" },
      { "S",     function() require("flash").treesitter() end,        mode = { "n", "x", "o" }, desc = "Flash: Treesitter" },
      { "r",     function() require("flash").remote() end,            mode = "o",               desc = "Flash: zdalne" },
      { "<C-s>", function() require("flash").toggle() end,            mode = "c",               desc = "Flash: toggle" },
    },
  },

  -- Trouble: panel błędów LSP, quickfix, loclist (<leader>xx i <leader>d*)
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = { focus = true },
  },

  -- TODO-komentarze: podświetla TODO/FIXME/NOTE + Telescope (<leader>ft)
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = { signs = true },
  },

  -- Szukanie plików / tekstu
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      defaults = {
        prompt_prefix = "   ",
        sorting_strategy = "ascending",
        layout_config = { horizontal = { prompt_position = "top" } },
      },
    },
  },

  -- Drzewo plików
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      hijack_netrw = true,
      -- `nvim .` obsługuje config/autocmds.lua (pusty bufor + terminal), nie drzewo
      hijack_directories = { enable = false },
      sync_root_with_cwd = true,
      update_focused_file = { enable = true, update_root = false },
      view = { width = 30, preserve_window_proportions = true },
      renderer = { root_folder_label = false, highlight_git = true },
      filters = { dotfiles = false },
      git = { ignore = false },
    },
  },

  -- Oznaczenia zmian git przy numerach linii
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {},
  },

  -- Automatyczne domykanie nawiasów i cudzysłowów
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = { fast_wrap = {}, disable_filetype = { "TelescopePrompt", "vim" } },
  },

  -- Terminale wysuwane (Alt+h / Alt+v / Alt+i, patrz config/terms.lua)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    lazy = true,
    opts = {
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return math.floor(vim.o.columns * 0.4)
        end
      end,
      shade_terminals = false,
      float_opts = { border = "rounded" },
    },
  },
}
