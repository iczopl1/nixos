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
        "lua", "vim", "vimdoc", "query",
        "python", "c", "cpp", "java", "kotlin", "go",
        "bash", "nix", "json", "yaml", "toml",
        "markdown", "markdown_inline",
        "html", "css", "javascript",
      },
      -- bez "latex": ten parser wymaga tree-sitter CLI; LaTeX koloruje vimtex
      auto_install = false,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
