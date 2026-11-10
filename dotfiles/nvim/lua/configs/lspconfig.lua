local lspconfig = require "nvchad.configs.lspconfig"

dofile(vim.g.base46_cache .. "lsp")
require("nvchad.lsp").diagnostic_config()

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    lspconfig.on_attach(_, args.buf)
  end,
})

local lua_lsp_settings = {
  Lua = {
    runtime = { version = "LuaJIT" },
    workspace = {
      library = {
        vim.fn.expand "$VIMRUNTIME/lua",
        vim.fn.stdpath "data" .. "/lazy/ui/nvchad_types",
        vim.fn.stdpath "data" .. "/lazy/lazy.nvim/lua/lazy",
        "${3rd}/luv/library",
      },
    },
  },
}

local get_python_venv = function(root_dir)
  local candidates = {}

  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
    table.insert(candidates, vim.env.VIRTUAL_ENV)
  end

  for _, name in ipairs { ".venv", "venv" } do
    table.insert(candidates, root_dir .. "/" .. name)
  end

  for _, path in ipairs(candidates) do
    if vim.fn.executable(path .. "/bin/python") == 1 then
      return path
    end
  end
end

local activate_python_venv = function(venv)
  local bin = venv .. "/bin"

  vim.env.VIRTUAL_ENV = venv

  if not vim.env.PATH or not vim.env.PATH:find(bin, 1, true) then
    vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
  end
end

local pyright_settings = function(root_dir)
  local venv = get_python_venv(root_dir)

  if not venv then
    return {}
  end

  activate_python_venv(venv)

  return {
    python = {
      pythonPath = venv .. "/bin/python",
      analysis = {
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        extraPaths = {
          root_dir,
        },
      },
    },
  }
end

local on_init = function(client, _)
  local supports_semantic_tokens

  if vim.fn.has "nvim-0.11" == 1 then
    supports_semantic_tokens = client:supports_method "textDocument/semanticTokens"
  else
    supports_semantic_tokens = client.supports_method "textDocument/semanticTokens"
  end

  if supports_semantic_tokens then
    client.server_capabilities.semanticTokensProvider = nil
  end
end

if vim.lsp.config then
  vim.lsp.config("*", {
    capabilities = lspconfig.capabilities,
    on_init = on_init,
  })

  vim.lsp.config("lua_ls", {
    settings = lua_lsp_settings,
  })

  vim.lsp.config("pyright", {
    root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
    settings = pyright_settings(vim.fn.getcwd()),
    on_new_config = function(new_config, root_dir)
      new_config.settings = pyright_settings(root_dir)
    end,
  })

  vim.lsp.enable "lua_ls"
  vim.lsp.enable "pyright"
else
  require("lspconfig").lua_ls.setup {
    capabilities = lspconfig.capabilities,
    on_init = on_init,
    settings = lua_lsp_settings,
  }

  require("lspconfig").pyright.setup {
    capabilities = lspconfig.capabilities,
    on_init = on_init,
    root_dir = require("lspconfig.util").root_pattern("pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git"),
    on_new_config = function(new_config, root_dir)
      new_config.settings = pyright_settings(root_dir)
    end,
  }
end
