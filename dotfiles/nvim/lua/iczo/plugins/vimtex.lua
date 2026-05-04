return{
    {
    "lervag/vimtex",
  lazy = false,     -- we don't want to lazy load VimTeX
 
    config = function()
      vim.g.vimtex_view_method = 'zathura'  -- Use Zathura as the PDF viewer
      vim.g.vimtex_compiler_method = 'latexrun'  -- Use latexrun as the compiler
    end
  }
}
