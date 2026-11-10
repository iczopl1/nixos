-- Debugger (DAP). Adaptery z NixOS zamiast Masona:
--   Python  -> debugpy z python.nix (`python3 -m debugpy`)
--   C / C++ -> lldb-dap z pakietu lldb (programs.nix)
--   STM32   -> arm-none-eabi-gdb w trybie DAP (gdb >= 14) + OpenOCD na :3333
--              (gcc-arm-embedded i openocd NIE są instalowane - patrz doc/do-zrobienia.md)
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "mfussenegger/nvim-dap-python",
    },
    keys = {
      { "<leader>db", "<cmd>DapToggleBreakpoint<CR>", desc = "Breakpoint on/off" },
      { "<leader>dr", "<cmd>DapContinue<CR>", desc = "Start / kontynuuj" },
      { "<leader>do", "<cmd>DapStepOver<CR>", desc = "Krok (nad)" },
      { "<leader>di", "<cmd>DapStepInto<CR>", desc = "Krok (do środka)" },
      { "<leader>dO", "<cmd>DapStepOut<CR>", desc = "Krok (wyjdź)" },
      { "<leader>dq", "<cmd>DapTerminate<CR>", desc = "Zakończ" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Panel debuggera on/off" },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup()
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

      -- Python: interpreter z python.nix ma debugpy
      require("dap-python").setup("python3")

      -- C / C++ na tym komputerze
      dap.adapters.lldb = { type = "executable", command = "lldb-dap", name = "lldb" }

      -- STM32 przez OpenOCD (localhost:3333)
      dap.adapters["arm-gdb"] = {
        type = "executable",
        command = "arm-none-eabi-gdb",
        args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
      }

      local native = {
        name = "Uruchom program (lldb)",
        type = "lldb",
        request = "launch",
        program = function()
          return vim.fn.input("Program: ", vim.fn.getcwd() .. "/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
      }

      dap.configurations.c = {
        native,
        {
          name = "STM32 (OpenOCD :3333)",
          type = "arm-gdb",
          request = "attach",
          program = "${workspaceFolder}/output/program.elf",
          target = "localhost:3333",
          cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.cpp = { native }
    end,
  },
}
