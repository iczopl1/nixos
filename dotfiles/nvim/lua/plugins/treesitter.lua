-- Kolorowanie składni (treesitter). Parsery kompiluje gcc przy pierwszym otwarciu pliku.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    main = "nvim-treesitter.configs",
    opts = {
      ensure_installed = {
        -- Core nvim
        "lua", "vim", "vimdoc", "query",
        -- Systemy / skrypty
        "bash", "nix", "cmake", "dockerfile", "make",
        -- Języki (minimal)
        "python", "c", "cpp",
        -- Języki (full)
        "java", "kotlin", "go", "rust", "typescript", "javascript",
        -- Dane / konfiguracja
        "json", "yaml", "toml", "xml", "sql",
        -- Web
        "html", "css",
        -- Dokumentacja
        "markdown", "markdown_inline",
      },
      -- bez "latex": ten parser wymaga tree-sitter CLI; LaTeX koloruje vimtex
      auto_install = false,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
