-- Formatowanie przy zapisie (conform). Formatery z NixOS:
--   stylua (programs.nix), black (python.nix), clang-format (clang-tools),
--   google-java-format (programs.nix), nixfmt-rfc-style (programs_minimal.nix),
--   prettier (programs.nix/full).
return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        lua        = { "stylua" },
        python     = { "black" },
        c          = { "clang-format" },
        cpp        = { "clang-format" },
        java       = { "google-java-format" },
        nix        = { "nixfmt" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        json       = { "prettier" },
        css        = { "prettier" },
        html       = { "prettier" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },
}
