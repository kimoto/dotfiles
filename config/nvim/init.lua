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
  }
}
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
vim.keymap.set('n', '<leader>fr', ':Telescope frecency<CR>', {})

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
