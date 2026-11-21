-- Uzupełnianie: blink.cmp (zamiast nvim-cmp + LuaSnip z NvChada).
-- Snippety: friendly-snippets przez wbudowane vim.snippet.
return {
  {
    "saghen/blink.cmp",
    version = "1.*", -- wersja z gotowym modułem dopasowywania (Rust)
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      -- Klawisze jak w NvChad: Enter = zatwierdź, Tab / Shift+Tab = następna / poprzednia pozycja
      keymap = {
        preset = "enter",
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        list = { selection = { preselect = true, auto_insert = false } },
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
        menu = { border = "rounded" },
      },
      signature = { enabled = true },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      -- Gdy gotowy moduł Rust się nie pobierze, działa wersja w Lua (wolniejsza) z ostrzeżeniem.
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },
}
