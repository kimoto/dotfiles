require('nvim-tree').setup({
  sort_by = 'case_sensitive',
  view = {
    adaptive_size = false,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = false
  },
})
