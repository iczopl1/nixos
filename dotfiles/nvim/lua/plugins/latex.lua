-- LaTeX (vimtex). Podgląd PDF: zathura, kompilacja: latexmk (z texliveFull).
-- Wcześniej było `latexrun`, ale nie był instalowany - latexmk jest w texliveFull.
-- Skróty vimtex zaczynają się od <leader>l (\l w domyślnym vimtex), np.:
--   <leader>ll kompiluj (ciągle), <leader>lv podgląd, <leader>lc wyczyść, <leader>le błędy
return {
  {
    "lervag/vimtex",
    lazy = false, -- vimtex nie lubi leniwego ładowania
    init = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"
    end,
  },
}
