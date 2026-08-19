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
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
vim.keymap.set('n', '<leader>fr', ':Telescope frecency<CR>', { desc = 'Recent files (frecency)' })

-- Pickers that were already installed but had no key on them. <leader>ff/fg
-- only find things by name or content; these three are the ones you reach for
-- when you know *when* you touched a file, not what it was called.
vim.keymap.set('n', '<leader>fo', builtin.oldfiles, { desc = 'Previously opened files' })
vim.keymap.set('n', '<leader>fs', builtin.git_status, { desc = 'Changed files (git status)' })
vim.keymap.set('n', '<leader>fl', builtin.resume, { desc = 'Reopen the last picker' })
