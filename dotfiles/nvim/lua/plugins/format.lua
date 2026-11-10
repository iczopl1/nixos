-- Formatowanie przy zapisie (conform). Formatery z NixOS:
--   stylua (programs.nix), black (python.nix), clang-format (clang-tools),
--   google-java-format (programs.nix).
return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "black" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        java = { "google-java-format" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },
}
