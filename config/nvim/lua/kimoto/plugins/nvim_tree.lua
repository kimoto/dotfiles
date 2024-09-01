require('nvim-tree').setup({
  sort_by = 'case_sensitive',
  view = {
    adaptive_size = false,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
--  actions = {
--    open_file = {
--      quit_on_open = true,
--    },
--  },
})

-- start neovim with open nvim-tree
-- require("nvim-tree.api").tree.toggle(false, true)
