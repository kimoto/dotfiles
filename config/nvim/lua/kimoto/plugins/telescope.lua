-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
require('telescope').setup {
  pickers = {
    -- rg でファイル列挙: 隠しファイルとシンボリックリンク先も含め、.git は除く
    find_files = {
      find_command = { 'rg', '--files', '--hidden', '-g', '!.git', '-L' },
    },
  },
  extensions = {
    frecency = {
      db_safe_mode = false, -- 古いエントリの自動削除時に確認を求めない
    },
  },
}

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files)
vim.keymap.set('n', '<leader>fg', builtin.live_grep)
vim.keymap.set('n', '<leader>fb', builtin.buffers)
vim.keymap.set('n', '<leader>fh', builtin.help_tags)
vim.keymap.set('n', '<leader>fr', ':Telescope frecency<CR>')
