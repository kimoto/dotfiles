-- Ring-aware yank/put: p/P go through yanky so <C-p>/<C-n> can cycle the ring
-- right after a put.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
require('yanky').setup({
  ring = {
    history_length = 100,
    storage = 'shada',
    sync_with_numbered_registers = true,
    cancel_event = 'update',
    ignore_registers = { '_' },
    update_register_on_cycle = false,
  },
  system_clipboard = {
    sync_with_ring = true,
  },
})

vim.keymap.set({ 'n', 'x' }, 'p', '<Plug>(YankyPutAfter)')
vim.keymap.set({ 'n', 'x' }, 'P', '<Plug>(YankyPutBefore)')
vim.keymap.set({ 'n', 'x' }, 'gp', '<Plug>(YankyGPutAfter)')
vim.keymap.set({ 'n', 'x' }, 'gP', '<Plug>(YankyGPutBefore)')
vim.keymap.set('n', '<C-p>', '<Plug>(YankyPreviousEntry)')
vim.keymap.set('n', '<C-n>', '<Plug>(YankyNextEntry)')
