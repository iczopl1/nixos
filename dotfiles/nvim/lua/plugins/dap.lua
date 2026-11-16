-- Debugger (DAP). Adaptery z NixOS zamiast Masona:
--   Python  -> debugpy z python.nix (`python3 -m debugpy`); interpreter projektu wykrywany
--              tak samo jak w LSP (lua/config/util.lua: .venv/ -> venv/ -> globalny python).
--              Walidacja bin/python (nie samo istnienie folderu) – inaczej np. "venv/"
--              zsynchronizowany z Windows (venv/Scripts/python.exe) zostałby błędnie użyty.
--              <leader>dr z >1 konfiguracją pyta który plik odpalić (aktualny / main.py).
--   C / C++ -> lldb-dap z pakietu lldb (programs.nix)
--   STM32   -> arm-none-eabi-gdb w trybie DAP (gdb >= 14) + st-util (stlink, :4242)
--              Konfiguracja "STM32" sama odpala `make debug` w katalogu projektu
--              (konwencja Makefile – patrz `agent` w terminalu) i szuka .elf w build/debug/.
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

      -- Python: adapter (debugpy) odpalany globalnym python3 z python.nix.
      -- Interpreter PROGRAMU (pythonPath) – osobna sprawa, patrz resolve_python niżej.
      local dap_python = require("dap-python")
      dap_python.setup("python3")

      -- Interpreter projektu: .venv/ -> venv/ -> nil (nil = dap-python nie ustawia
      -- pythonPath, debugpy używa interpretera adaptera, czyli globalnego python3).
      -- Ta sama logika co pyright (lsp.lua) – LSP i debugger zawsze się zgadzają.
      local util = require("config.util")
      dap_python.resolve_python = function()
        local venv = util.python_venv(vim.fn.getcwd())
        return venv and (venv .. "/bin/python") or nil
      end

      -- Dodatkowa konfiguracja: odpal main.py w katalogu projektu (obok domyślnej
      -- "file" = aktualny bufor z dap-python). Z >1 konfiguracją <leader>dr pyta, którą
      -- odpalić – to jest to pytanie "main.py czy aktualny plik".
      -- pythonPath celowo pominięty – enrich_config dap-python i tak go dopełni
      -- przez resolve_python ustawiony wyżej (ta sama ścieżka co w "file" domyślnym).
      table.insert(require("dap").configurations.python, 2, {
        type = "python",
        request = "launch",
        name = "main.py",
        program = "${workspaceFolder}/main.py",
      })

      -- C / C++ na tym komputerze
      dap.adapters.lldb = { type = "executable", command = "lldb-dap", name = "lldb" }

      -- STM32 przez st-util (stlink) – ten sam toolchain co `make push` w Makefile projektu.
      -- UWAGA: `gdb` (host, multiarch), NIE `arm-none-eabi-gdb` – ten z gcc-arm-embedded
      -- jest budowany --without-python, więc --interpreter=dap w ogóle nie startuje.
      -- Plain `gdb` ma --enable-targets=all + python, architekturę ARM rozpoznaje z .elf.
      dap.adapters["arm-gdb"] = {
        type = "executable",
        command = "gdb",
        args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
      }

      -- Jeden st-util na raz – zabij poprzedni, jeśli debugowanie startuje ponownie
      local stutil_job = nil
      local function stop_stutil()
        if stutil_job then
          vim.fn.jobstop(stutil_job)
          stutil_job = nil
        end
      end
      dap.listeners.after.event_terminated["stm32_stutil"] = stop_stutil
      dap.listeners.after.event_exited["stm32_stutil"] = stop_stutil

      -- Odpala `make debug` w katalogu projektu (konwencja Makefile – patrz `agent`),
      -- szuka wynikowego .elf w build/debug/ i startuje st-util (gdbserver na :4242).
      -- Dzięki temu debugger zawsze używa tego samego Makefile co normalny build/flash
      -- – nowe pliki .c/.h podłączone w Makefile od razu działają, bez osobnej konfiguracji.
      local function stm32_build_and_launch()
        local root = vim.fn.getcwd()
        vim.notify("STM32: make debug…", vim.log.levels.INFO)
        vim.fn.system({ "make", "-C", root, "debug" })
        if vim.v.shell_error ~= 0 then
          error("make debug nie powiodło się (sprawdź błędy kompilacji w :messages)")
        end
        local elf = vim.fn.glob(root .. "/build/debug/*.elf")
        if elf == "" then
          error("Brak .elf w build/debug/ po `make debug` – sprawdź Makefile")
        end
        stop_stutil()
        stutil_job = vim.fn.jobstart({ "st-util" })
        vim.wait(300) -- chwila, żeby st-util wystartował gdbserver przed podłączeniem gdb
        return elf
      end

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
          name = "STM32: make debug + st-util (ST-Link)",
          type = "arm-gdb",
          request = "launch",
          program = stm32_build_and_launch,
          target = "extended-remote localhost:4242",
          cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.cpp = { native }
    end,
  },
}
