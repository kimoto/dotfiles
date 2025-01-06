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
  highlights = {
    separator = {
      fg = '#073642',
      bg = '#000000',
    },
    background = {
      fg = '#657b83',
      bg = '#444444'
    },
    buffer_selected = {
      fg = '#ffffff',
      bg = '#000000',
      bold = true,
    },
    fill = {
      bg = '#073642'
    }
  },
})

vim.keymap.set('n', '<Tab>', '<Cmd>BufferLineCycleNext<CR>', {})
vim.keymap.set('n', '<S-Tab>', '<Cmd>BufferLineCyclePrev<CR>', {})
