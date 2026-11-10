-- Wygląd: motyw, pasek stanu, pasek buforów, podpowiedzi skrótów, wcięcia.
return {
  -- Motyw (jak w NvChad: catppuccin)
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        blink_cmp = true,
        gitsigns = true,
        nvimtree = true,
        telescope = { enabled = true },
        which_key = true,
        indent_blankline = { enabled = true },
        native_lsp = { enabled = true },
        dap = true,
        dap_ui = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- Pasek stanu na dole
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "catppuccin",
        globalstatus = true,
        section_separators = { left = "", right = "" },
        component_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = { "NvimTree" } },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "lsp_status", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  -- Pasek buforów u góry (wygląda jak karty)
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        mode = "buffers",
        numbers = "ordinal", -- numer = Alt+<numer>
        close_command = function(buf)
          require("config.util").close_buffer(buf)
        end,
        diagnostics = "nvim_lsp",
        show_buffer_close_icons = false,
        offsets = {
          { filetype = "NvimTree", text = "Pliki", highlight = "Directory", separator = true },
        },
      },
    },
  },

  -- Podpowiedzi skrótów po naciśnięciu Spacji
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      spec = {
        { "<leader>b", group = "bufory" },
        { "<leader>t", group = "karty / motyw" },
        { "<leader>f", group = "szukaj / formatuj" },
        { "<leader>d", group = "debugger / diagnostyka" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "LaTeX (vimtex)" },
      },
    },
  },

  -- Linie wcięć
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = { scope = { enabled = true } },
  },
}
