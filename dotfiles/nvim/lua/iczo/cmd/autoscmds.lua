local function find_latex_main()
  local handle = io.popen("find . -maxdepth 1 -name '*.latexmain'")
  local main_file = handle:read("*l")
  handle:close()
  if main_file then
    return main_file
  else
    return nil
  end
end

vim.g.vimtex_main_file = find_latex_main()
