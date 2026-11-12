-- LSP. Serwery są instalowane przez NixOS (nie Mason):
-- minimal: lua_ls, pyright, clangd, texlab, nil_ls, bashls, yamlls, marksman, neocmake
-- full:    + java_language_server, ts_ls, html/cssls/jsonls, rust_analyzer, gopls, kotlin_language_server
-- nvim-lspconfig dostarcza tylko gotowe ustawienia (komendy, root_markers).

-- Python: użyj venv projektu ($VIRTUAL_ENV, .venv/, venv/) - jak w starej konfiguracji.
local function python_venv(root_dir)
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

local function pyright_settings(root_dir)
  local venv = python_venv(root_dir)
  if not venv then
    return {}
  end
  -- "aktywuj" venv dla nvim (terminale i narzędzia widzą jego python)
  vim.env.VIRTUAL_ENV = venv
  local bin = venv .. "/bin"
  if not (vim.env.PATH or ""):find(bin, 1, true) then
    vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
  end
  return {
    python = {
      pythonPath = bin .. "/python",
      analysis = {
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        extraPaths = { root_dir },
      },
    },
  }
end

-- Skróty dostępne, gdy LSP jest podłączony do bufora (jak w NvChad).
local function on_attach(buf)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = "LSP: " .. desc })
  end
  map("n", "gD", vim.lsp.buf.declaration, "deklaracja")
  map("n", "gd", vim.lsp.buf.definition, "definicja")
  map("n", "gi", vim.lsp.buf.implementation, "implementacja")
  map("n", "gr", "<cmd>Telescope lsp_references<CR>", "użycia")
  map("n", "K", vim.lsp.buf.hover, "opis")
  map("n", "<leader>sh", vim.lsp.buf.signature_help, "sygnatura")
  map("n", "<leader>D", vim.lsp.buf.type_definition, "definicja typu")
  map("n", "<leader>ra", vim.lsp.buf.rename, "zmień nazwę")
  map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "akcje kodu")
  map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, "dodaj folder roboczy")
  map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, "usuń folder roboczy")
  map("n", "<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, "lista folderów roboczych")
end

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "saghen/blink.cmp" },
    config = function()
      -- Wygląd diagnostyki
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded" },
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp", { clear = true }),
        callback = function(ev)
          on_attach(ev.buf)
          -- jak w NvChad: bez kolorowania semantycznego (zostaje treesitter)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client then
            client.server_capabilities.semanticTokensProvider = nil
          end
        end,
      })

      -- Wspólne dla wszystkich serwerów: możliwości uzupełniania z blink.cmp
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = {
              checkThirdParty = false,
              library = { vim.env.VIMRUNTIME },
            },
          },
        },
      })

      vim.lsp.config("pyright", {
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        before_init = function(_, config)
          config.settings = vim.tbl_deep_extend("force", config.settings or {}, pyright_settings(config.root_dir))
        end,
      })

      vim.lsp.config("clangd", {})

      vim.lsp.config("java_language_server", {
        cmd = { "java-language-server" },
      })

      vim.lsp.config("texlab", {})

      vim.lsp.config("nil_ls", {
        settings = {
          ["nil"] = {
            formatting = { command = { "nixfmt" } },
            nix = { flake = { autoArchive = false } },
          },
        },
      })

      -- minimal: Bash, YAML, Markdown
      vim.lsp.config("bashls", {})
      vim.lsp.config("yamlls", {
        settings = {
          yaml = { validate = true, format = { enable = true } },
        },
      })
      vim.lsp.config("marksman", {})

      -- full: JS/TS, HTML/CSS/JSON, Rust, Go, Kotlin
      vim.lsp.config("ts_ls", {})
      vim.lsp.config("html", {})
      vim.lsp.config("cssls", {})
      vim.lsp.config("jsonls", {})
      vim.lsp.config("rust_analyzer", {
        settings = {
          ["rust-analyzer"] = {
            checkOnSave = { command = "clippy" },
          },
        },
      })
      vim.lsp.config("gopls", {})
      vim.lsp.config("kotlin_language_server", {})
      vim.lsp.config("neocmake", {})    -- cmake-language-server (z nixpkgs, minimal+full)

      -- enable: uruchamia serwer gdy plik pasuje do filetype (auto z nvim-lspconfig)
      vim.lsp.enable({
        -- minimal
        "lua_ls", "pyright", "clangd", "texlab", "nil_ls",
        "bashls", "yamlls", "marksman", "neocmake",
        -- full
        "java_language_server", "ts_ls", "html", "cssls", "jsonls",
        "rust_analyzer", "gopls", "kotlin_language_server",
      })
    end,
  },
}
