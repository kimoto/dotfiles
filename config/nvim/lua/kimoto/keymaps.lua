-- Editor-wide maps that belong to no single plugin.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.

-- ウィンドウを移動する
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Window: focus right' })
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Window: focus left' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Window: focus down' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Window: focus up' })

-- バッファを番号で直接開く / 前後に移動する
for i = 1, 6 do
  vim.keymap.set('n', '<leader>' .. i, ':b ' .. i .. '<CR>', { desc = 'Buffer ' .. i })
end
vim.keymap.set('n', '<leader>n', ':bn<CR>', { desc = 'Buffer: next' })
vim.keymap.set('n', '<leader>p', ':bp<CR>', { desc = 'Buffer: previous' })

-- <Tab> is BufferLineCycleNext (plugins/bufferline.lua), and in a terminal
-- without the kitty keyboard protocol <C-i> arrives as the very same byte
-- (0x09) — so cycling buffers silently ate <C-i>, the jumplist's forward
-- motion, leaving <C-o> a one-way trip.
--
-- Mapping it back is purely additive. Measured with this repo's .tmux.conf:
-- a legacy 0x09 resolves to the <Tab> map either way (buffer cycling is
-- unchanged), while the protocol's own encoding for Ctrl+I (CSI 105;5u)
-- resolves to this one. Order of definition does not matter.
vim.keymap.set('n', '<C-i>', '<C-i>', { desc = 'Jump forward (jumplist)' })

-- 検索のハイライトを消す。:nohlsearch を打つより Esc のほうが手が先に動く
vim.keymap.set('n', '<Esc>', '<Cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })
