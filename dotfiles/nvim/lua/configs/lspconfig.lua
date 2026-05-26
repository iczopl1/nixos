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

  vim.lsp.enable "lua_ls"
else
  require("lspconfig").lua_ls.setup {
    capabilities = lspconfig.capabilities,
    on_init = on_init,
    settings = lua_lsp_settings,
  }
end
