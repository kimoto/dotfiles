-- Editor-wide maps that belong to no single plugin.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.

-- ウィンドウを移動する
vim.keymap.set('n', '<C-l>', '<C-w>l')
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-j>', '<C-w>j')
vim.keymap.set('n', '<C-k>', '<C-w>k')

-- バッファを番号で直接開く / 前後に移動する
for i = 1, 6 do
  vim.keymap.set('n', '<leader>' .. i, ':b ' .. i .. '<CR>')
end
vim.keymap.set('n', '<leader>n', ':bn<CR>')
vim.keymap.set('n', '<leader>p', ':bp<CR>')
