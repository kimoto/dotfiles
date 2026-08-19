-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
-- No custom highlights: colors are derived from the active colorscheme.
require('bufferline').setup({
  options = {
    separator_style = 'thick',
    show_buffer_close_icons = true,
    show_close_icon = true,
    color_icons = true,
  },
})

vim.keymap.set('n', '<Tab>', '<Cmd>BufferLineCycleNext<CR>', { desc = 'Buffer: cycle next' })
vim.keymap.set('n', '<S-Tab>', '<Cmd>BufferLineCyclePrev<CR>', { desc = 'Buffer: cycle previous' })
