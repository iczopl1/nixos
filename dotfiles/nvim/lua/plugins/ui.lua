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
    dependencies = { "nvim-tree/nvim-web-devicons", "catppuccin/nvim" },
    opts = {
      options = {
        theme = "catppuccin",
        globalstatus = true,
        section_separators = { left = "", right = "" },
        component_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = { "NvimTree" } },
        refresh = { statusline = 300 },  -- odśwież co 300 ms (WPM + CursorLine)
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = {
          {
            function()
              local clients = vim.lsp.get_clients({ bufnr = 0 })
              if #clients == 0 then return "" end
              return "󰒍 " .. table.concat(vim.tbl_map(function(c) return c.name end, clients), " ")
            end,
          },
          "filetype",
        },
        lualine_y = { "progress" },
        lualine_z = {
          -- T3.5: licznik WPM – widoczny tylko w trybie wpisywania, kolor zmienia się z prędkością
          {
            function()
              local ok, ts = pcall(require, "config.typing_speed")
              if not ok then return "" end
              local wpm = ts.get_wpm()
              return wpm > 0 and (wpm .. " wpm") or ""
            end,
            color = function()
              local ok, ts = pcall(require, "config.typing_speed")
              if not ok then return {} end
              return { fg = ts.wpm_fg(ts.get_wpm()), gui = "bold" }
            end,
            cond = function() return vim.fn.mode() == "i" end,
          },
          "location",
        },
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

  -- Podpowiedzi skrótów po naciśnięciu Spacji (lub innego prefiksu)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 400,
      spec = {
        -- <leader> grupy
        { "<leader>b", group = "bufory" },
        { "<leader>t", group = "karty / motyw" },
        { "<leader>f", group = "szukaj / pliki" },
        { "<leader>d", group = "debugger / diagnostyka" },
        { "<leader>x", group = "trouble / zamknij bufor" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "LaTeX (vimtex)" },
        { "<leader>s", group = "LSP: podpis / sygnatura" },
        { "<leader>w", group = "LSP: workspace / which-key" },
        { "<leader>r", group = "zmień nazwę / relativenumber" },
        { "<leader>c", group = "akcje kodu" },
        -- nawigacja
        { "[",  group = "poprzedni" },
        { "]",  group = "następny" },
        { "g",  group = "idź do / nawigacja" },
        -- terminale
        { "<A-h>", desc = "Terminal poziomy" },
        { "<A-v>", desc = "Terminal pionowy" },
        { "<A-i>", desc = "Terminal pływający" },
      },
    },
  },

  -- Linie wcięć
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = { scope = { enabled = true } },
  },

  -- Dashboard: ekran startowy (alpha-nvim) – skróty do nowych plików, ostatnich plików
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")
      dashboard.section.header.val = {
        "                                   ",
        "   ⣴⣶⣤⡤⠦⣤⣀⣤⠆     ⣈⣭⣿⣶⣿⣦⣼⣆          ",
        "    ⠉⠻⢿⣿⠿⣿⣿⣶⣦⠤⠄⡠⢾⣿⣿⡿⠋⠉⠉⠻⣿⣿⡛⣦       ",
        "          ⠈⢿⣿⣟⠦ ⣾⣿⣿⣷    ⠻⠿⢿⣿⣧⣄     ",
        "           ⣸⣿⣿⢧ ⢻⠻⣿⣿⣷⣄⣀⠄⠢⣀⡀⠈⠙⠿⠄    ",
        "          ⢠⣿⣿⣿⠈    ⣻⣿⣿⣿⣿⣿⣿⣿⣛⣳⣤⣀⣀   ",
        "   ⢠⣧⣶⣥⡤⢄ ⣸⣿⣿⠘  ⢀⣴⣿⣿⡿⠛⣿⣿⣧⠈⢿⠿⠟⠛⠻⠿⠄  ",
        "  ⣰⣿⣿⠛⠻⣿⣿⡦⢹⣿⣷   ⢊⣿⣿⡏  ⢸⣿⣿⡇ ⢀⣠⣄⣾⠄   ",
        " ⣠⣿⠿⠛ ⢀⣿⣿⣷⠘⢿⣿⣦⡀ ⢸⢿⣿⣿⣄ ⣸⣿⣿⡇⣪⣿⡿⠿⣿⣷⡄  ",
        " ⠙⠃   ⣼⣿⡟  ⠈⠻⣿⣿⣦⣌⡇⠻⣿⣿⣷⣿⣿⣿ ⣿⣿⡇ ⠛⠻⢷⣄ ",
        "      ⢻⣿⣿⣄   ⠈⠻⣿⣿⣿⣷⣿⣿⣿⣿⣿⡟ ⠫⢿⣿⡆     ",
        "       ⠻⣿⣿⣿⣿⣶⣶⣾⣿⣿⣿⣿⣿⣿⣿⣿⡟⢀⣀⣤⣾⡿⠃     ",
        "                                   ",
      }
      dashboard.section.buttons.val = {
        dashboard.button("n", "  Nowy plik",          ":ene <BAR> startinsert <CR>"),
        dashboard.button("f", "  Szukaj pliku",       ":Telescope find_files <CR>"),
        dashboard.button("r", "  Ostatnie pliki",     ":Telescope oldfiles <CR>"),
        dashboard.button("w", "  Szukaj tekstu",      ":Telescope live_grep <CR>"),
        dashboard.button("q", "  Wyjście",            ":qa<CR>"),
      }
      alpha.setup(dashboard.opts)
      -- Nie otwieraj dashboardu gdy nvim otwiera plik/katalog (autocmds.lua to obsługuje)
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyVimStarted",
        callback = function()
          local stats = require("lazy").stats()
          dashboard.section.footer.val = "⚡ " .. stats.count .. " pluginów załadowano"
          pcall(vim.cmd.AlphaRedraw)
        end,
      })
    end,
  },

  -- Zen-mode: tryb skupienia (ukrywa pasek stanu, boczne elementy, centruje tekst)
  {
    "folke/zen-mode.nvim",
    cmd = "ZenMode",
    opts = {
      window = { width = 100 },
      plugins = {
        gitsigns = { enabled = false },
        tmux = { enabled = false },
      },
    },
  },

  -- Colorizer: podgląd kolorów hex/rgb/hsl bezpośrednio w edytorze
  {
    "NvChad/nvim-colorizer.lua",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      user_default_options = {
        RGB = true, RRGGBB = true, names = false,
        RRGGBBAA = true, css = true, css_fn = true,
        mode = "background",
      },
    },
  },

  -- Noice: ładniejsze powiadomienia, cmdline pływający, messages w popup
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    opts = {
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
        progress = { enabled = false }, -- pasek postępu LSP wyłączony (używamy lualine)
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = false,
      },
      notify = { enabled = true },
    },
  },
}
