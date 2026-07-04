require'bufferline'.setup({
  options = {
    -- mode = "tabs",
    separator_style = 'thick',
    -- separator_style = 'slant',
    -- always_show_bufferline = false,
    show_buffer_close_icons = true,
    show_close_icon = true,
    color_icons = true,
  },
  -- no custom highlights: derive colors from the active colorscheme (onedark)
})

-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
vim.keymap.set('n', '<Tab>', '<Cmd>BufferLineCycleNext<CR>', {})
vim.keymap.set('n', '<S-Tab>', '<Cmd>BufferLineCyclePrev<CR>', {})
