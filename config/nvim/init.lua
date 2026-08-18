-- NOTE: keybindings defined under lua/kimoto/ are documented in KEYBINDINGS.md
-- at the repo root — update it when adding or changing a map.

-- Set before anything defines a <leader> mapping, so every map below resolves
-- against Space.
vim.g.mapleader = ' '

require('kimoto/basic_config')
require('kimoto/setup_plugin')
require('kimoto/keymaps')

require('kimoto/plugins/lualine')
require('kimoto/plugins/nvim_cursorline')
require('kimoto/plugins/gitsigns')
require('kimoto/plugins/auto_save')
require('kimoto/plugins/bufferline')
require('kimoto/plugins/nvim_tree')
require('kimoto/plugins/toggleterm')
require('kimoto/plugins/yanky')
require('kimoto/plugins/telescope')
require('kimoto/plugins/treesitter')
require('kimoto/plugins/colorscheme')
require('kimoto/plugins/lsp')
require('kimoto/plugins/dap')
