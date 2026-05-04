return{ 
  { "nvimtools/none-ls.nvim",
    ft = {"python","c","cpp","latex","java"},
        event = "VeryLazy",
        opts = function ()
          return require "iczo.configs.none-ls"
        end,
      },
  }
