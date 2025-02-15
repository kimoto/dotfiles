require('kimoto/basic_config')
require('kimoto/setup_plugin')
require('kimoto/plugins/lualine')
require('kimoto/plugins/nvim_cursorline')
require('kimoto/plugins/gitsigns')
require('kimoto/plugins/auto_save')
require('kimoto/plugins/bufferline')
require('kimoto/plugins/nvim_tree')
require('kimoto/plugins/toggleterm')
require("telescope").load_extension "file_browser"

vim.g.mapleader = ' '

vim.api.nvim_set_keymap('n', '<leader>e', ':NvimTreeToggle<CR>', {silent=true})

-- ウィンドウを移動する
vim.keymap.set('n', '<C-l>', '<C-w>l')
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-j>', '<C-w>j')
vim.keymap.set('n', '<C-k>', '<C-w>k')
vim.keymap.set('n', '<leader>1', ':b 1<CR>')
vim.keymap.set('n', '<leader>2', ':b 2<CR>')
vim.keymap.set('n', '<leader>3', ':b 3<CR>')
vim.keymap.set('n', '<leader>4', ':b 4<CR>')
vim.keymap.set('n', '<leader>5', ':b 5<CR>')
vim.keymap.set('n', '<leader>6', ':b 6<CR>')
vim.keymap.set('n', '<leader>n', ':bn<CR>')
vim.keymap.set('n', '<leader>p', ':bp<CR>')
vim.keymap.set('n', '<leader>t', ':ToggleTerm<CR>')
vim.keymap.set('n', '<D-l>', ':Telescope frecency<CR>')

vim.keymap.set({"n","x"}, "p", "<Plug>(YankyPutAfter)")
vim.keymap.set({"n","x"}, "P", "<Plug>(YankyPutBefore)")
vim.keymap.set({"n","x"}, "gp", "<Plug>(YankyGPutAfter)")
vim.keymap.set({"n","x"}, "gP", "<Plug>(YankyGPutBefore)")
vim.keymap.set("n", "<c-p>", "<Plug>(YankyPreviousEntry)")
vim.keymap.set("n", "<c-n>", "<Plug>(YankyNextEntry)")

require("yanky").setup({
  ring = {
    history_length = 100,
    storage = "shada",
    sync_with_numbered_registers = true,
    cancel_event = "update",
    ignore_registers = { "_" },
    update_register_on_cycle = false,
    permanent_wrapper = nil,
  },
  system_clipboard = {
    sync_with_ring = true,
  },
})

--vim.api.nvim_set_keymap(
--  "n",
--  "<space>ff",
--  ":Telescope file_browser<CR>",
--  { noremap = true }
--)
require('telescope').setup{
  defaults = {
    -- Default configuration for telescope goes here:
    -- config_key = value,
    mappings = {
      i = {
        -- map actions.which_key to <C-h> (default: <C-/>)
        -- actions.which_key shows the mappings for your picker,
        -- e.g. git_{create, delete, ...}_branch for the git_branches picker
        -- ["<C-h>"] = "which_key"
      }
    }
  },
  pickers = {
    -- Default configuration for builtin pickers goes here:
    -- picker_name = {
    --   picker_config_key = value,
    --   ...
    -- }
    find_files = {
      find_command = { "rg", "--files", "--hidden", "-g", "!.git", '-L' },
    }
    -- Now the picker_config_key will be applied every time you call this
    -- builtin picker
  },
  extensions = {
    -- Your extension configuration goes here:
    -- extension_name = {
    --   extension_config_key = value,
    -- }
    -- please take a look at the readme of the extension you want to configure
    frecency = {
      db_safe_mode = false, -- 古いエントリの自動削除時に確認を求めない
    }
  }
}
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
vim.keymap.set('n', '<leader>fr', ':Telescope frecency<CR>', {})

require('nvim-treesitter').setup {
  indent = {
    enable = true,
  },
}

require('git').setup()

-- color themes
-- vim.cmd('colorscheme solarized')
require('onedark').setup {
    style = 'deep'
}
require('onedark').load()

require('lualine').setup {
  options = {
    theme = 'onedark',
    globalstatus = true, -- 画面分割時にstatuslineを統合
  }
}

require('colorizer').setup()

-- coc
vim.g.coc_global_extensions = {'coc-toml', 'coc-json', 'coc-git', 'coc-prettier', 'coc-vetur', 'coc-tsserver', 'coc-solargraph', 'coc-perl', 'coc-json', 'coc-git', 'coc-java', 'coc-sql', 'coc-eslint', 'coc-prettier', 'coc-yank', 'coc-python', 'coc-css'}

-- related nvim-dap (debug adapter protocol)
vim.api.nvim_set_keymap('n', '<F5>', ':DapContinue<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<F9>', ':DapToggleBreakpoint<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<F10>', ':DapStepOver<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<F11>', ':DapStepInto<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<S-F11>', ':DapStepOut<CR>', { silent = true })
-- vim.api.nvim_set_keymap('n', '<leader>b', ':DapToggleBreakpoint<CR>', { silent = true })
-- vim.api.nvim_set_keymap('n', '<leader>B', ':lua require("dap").set_breakpoint(nil, nil, vim.fn.input("Breakpoint condition: "))<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<leader>lp', ':lua require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<leader>dr', ':lua require("dap").repl.open()<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<leader>dl', ':lua require("dap").run_last()<CR>', { silent = true })
vim.api.nvim_set_keymap('n', '<leader>d', ':lua require("dapui").toggle()<CR>', {})
require('dap-python').setup('python')
require('dap-ruby').setup()
require("dapui").setup()
local dap, dapui = require("dap"), require("dapui")
dap.listeners.before.attach.dapui_config = function()
  dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
  dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
  dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
  dapui.close()
end
-- require("dap-vscode-js").setup({
--   debugger_path = vim.fn.stdpath("data") .. "/site/pack/jetpack/opt/vscode-js-debug", -- Path to vscode-js-debug installation.
--   -- debugger_cmd = { "js-debug-adapter" }, -- Command to use to launch the debug server. Takes precedence over `node_path` and `debugger_path`.
--   adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' }, -- which adapters to register in nvim-dap
--   -- log_file_path = "(stdpath cache)/dap_vscode_js.log" -- Path for file logging
--   -- log_file_level = false -- Logging level for output to file. Set to false to disable file logging.
--   -- log_console_level = vim.log.levels.ERROR -- Logging level for output to console. Set to false to disable console output.
-- })
local dap = require("dap")

-- dap.adapters['pwa-node'] = {
--   type = 'server',
--   host = 'localhost',
--   port = '${port}',
--   executable = {
--     command = 'tsx',
--     args = {vim.fn.stdpath("data") .. "/site/pack/jetpack/opt/vscode-js-debug/src/dapDebugServer.ts", "${port}"},
--   },
-- }
--
-- for _, language in ipairs({ "typescript", "javascript" }) do
--   dap.configurations[language] = {
--     {
--       type = "pwa-node",
--       request = "launch",
--       name = "Launch file",
--       program = "${file}",
--       cwd = "${workspaceFolder}",
--       executable = {
--         command = "tsx",
--         -- 💀 Make sure to update this path to point to your installation
--         args = {vim.fn.stdpath("data") .. "/site/pack/jetpack/opt/vscode-js-debug/src/dapDebugServer.ts", "${port}"},
--       },
--     },
--   }
-- end
--
-- -- vim.g.auto_ctags = 1 -- tagsの自動更新
--
-- Vimを終了してもUndo
vim.opt.undofile = true
vim.opt.undodir = os.getenv("HOME") .. "/.cache/nvim/undodir"
