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
      -- markdown_inline wyłączony z highlight: wstrzyknięty parser czasem crashuje
      -- w silniku Neovima (vim/treesitter/languagetree.lua, "attempt to call" – błąd
      -- w core Neovima, NIE w tej wtyczce; branch main nic by tu nie zmienił, bo i tak
      -- używa tego samego core API). Patrz BROKEN.md. Parser zostaje zainstalowany
      -- (markdown wciąż koloruje nagłówki/bloki kodu/listy), nie koloruje tylko inline
      -- bold/italic/linków w tekście.
      highlight = { enable = true, disable = { "markdown_inline" } },
      indent = { enable = true },
    },
  },
}
