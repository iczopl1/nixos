-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local lspconfig = require "lspconfig"

-- EXAMPLE
local servers = { "html", "cssls", "pyright","clangd","texlab","jdtls"}
local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

lspconfig.pyright.setup({
  on_attach = nvlsp.on_attach,
  capabilities = nvlsp.capabilities,
  filetypes = {"python"},
})
lspconfig.clangd.setup({
  on_attach = nvlsp.on_attach,
  capabilities = nvlsp.capabilities,
  filetypes = {"c","c++","c#"}

})
lspconfig.texlab.setup({
  on_attach = nvlsp.on_attach,
  capabilities = nvlsp.capabilities,
  filetypes = {"latex","tex","latexmk"}

})
-- configuring single server, example: typescript
-- lspconfig.ts_ls.setup {
--   on_attach = nvlsp.on_attach,
--   on_init = nvlsp.on_init,
--   capabilities = nvlsp.capabilities,
-- }
