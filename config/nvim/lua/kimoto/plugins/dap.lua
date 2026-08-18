-- Debug Adapter Protocol: nvim-dap plus the python/ruby adapters and dap-ui.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
local dap = require('dap')
local dapui = require('dapui')

require('dap-python').setup('python')
require('dap-ruby').setup()
dapui.setup()

-- Open the UI when a session starts, close it when the debuggee goes away.
-- Wrapped, not passed directly: dap invokes listeners with (session, body),
-- which dapui.open/close would read as their own options argument.
local function open_ui() dapui.open() end
local function close_ui() dapui.close() end
dap.listeners.before.attach.dapui_config = open_ui
dap.listeners.before.launch.dapui_config = open_ui
dap.listeners.before.event_terminated.dapui_config = close_ui
dap.listeners.before.event_exited.dapui_config = close_ui

vim.keymap.set('n', '<F5>', dap.continue)
vim.keymap.set('n', '<F9>', dap.toggle_breakpoint)
vim.keymap.set('n', '<F10>', dap.step_over)
vim.keymap.set('n', '<F11>', dap.step_into)
vim.keymap.set('n', '<S-F11>', dap.step_out)
vim.keymap.set('n', '<leader>lp', function()
  dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
end)
vim.keymap.set('n', '<leader>dr', dap.repl.open)
vim.keymap.set('n', '<leader>dl', dap.run_last)
vim.keymap.set('n', '<leader>d', dapui.toggle)
