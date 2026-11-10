
local M = {}

M.setup = function()
  local dap = require("dap")
  vim.keymap.set("n", "<leader>db", "<cmd>DapToggleBreakpoint<CR>", { desc = "Add breakpoint at line" })
  vim.keymap.set("n", "<leader>dr", "<cmd>DapContinue<CR>", { desc = "Start or continue the debugger" })
  

dap.adapters.stm32 ={
  type = 'server',
  port = 3333,
  host = '127.0.0.1',
  executable = {
    --command = 'openocd',
    --args={
    --    '-f','interface/stlink.cfg',
    --    '-c','transport select hla_swd',
    --    '-c','adapter speed 500',
    --    '-c','set CPUTAPID 0x2ba01477',
        --'-f','target/stm32f1x.cfg',
      --   },
    command = 'arm-none-eabi-gdb',
    args={
        '--silent','--interpreter=mi2','-l','10000','-b','1000',
        },
    options ={
        timeout = 10000,
      },
  },
}
dap.configurations.c = {
  {
  name = 'Debug STM32',
  type = 'cdbg',
  request = 'launch',
  program = '${workspaceFolder}/output/program.elf',
  cwd= '$(workspaceFolder)',
  stopAtEntry = false,
  MIMode = "gdb",
  miDebuggerServerAddress = 'localhost:3333',
  serverLaunchTimeout = 5000,
  postRemoteConnectCommands = {
        {
        text = "monitor reset",
        ignoreFailures = false},{
        text = "load",
          ignoreFailures = false,
        }
      }
},
}
end
return M
