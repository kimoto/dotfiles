-- Diagnostics were virtual-text only: you could read the error on the line the
-- cursor happens to be on, and had no way to see the rest. Trouble lists them
-- for the buffer or the whole workspace, and does the same for the quickfix
-- and location lists.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
require('trouble').setup()

vim.keymap.set('n', '<leader>xx', '<Cmd>Trouble diagnostics toggle<CR>',
  { desc = 'Diagnostics (workspace)' })
vim.keymap.set('n', '<leader>xb', '<Cmd>Trouble diagnostics toggle filter.buf=0<CR>',
  { desc = 'Diagnostics (this buffer)' })
vim.keymap.set('n', '<leader>xq', '<Cmd>Trouble qflist toggle<CR>',
  { desc = 'Quickfix list' })
vim.keymap.set('n', '<leader>xl', '<Cmd>Trouble loclist toggle<CR>',
  { desc = 'Location list' })
