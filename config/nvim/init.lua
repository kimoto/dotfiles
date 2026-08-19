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
-- last: reads the `desc` of every map registered above
require('kimoto/plugins/which_key')

-- Deferred: neither of these is needed to paint the first screen, and together
-- they were ~28ms of a ~148ms startup — lsp ~23ms (mason, nvim-cmp, conform),
-- dap ~5ms — measured warm with nvim 0.12.4 via ./bin/nvim_startuptime.sh.
-- vim.schedule runs them on the first main-loop tick — the UI is already up and
-- nothing can have been typed yet, so this is invisible in use.
--
-- Safe for LSP specifically: vim.lsp.enable() called after VimEnter re-runs its
-- FileType autocmd over already-loaded buffers (`doautoall nvim.lsp.enable
-- FileType`), so `nvim foo.ts` still attaches. Only `dap`'s keymaps register
-- late, and they are function keys on a debugger that has to be started anyway.
vim.schedule(function()
  require('kimoto/plugins/lsp')
  require('kimoto/plugins/dap')
end)
