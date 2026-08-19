-- Key discovery: press a prefix (Space, g, z, ...) and the available follow-up
-- keys appear in a popup, labelled with the `desc` each map was registered
-- with. KEYBINDINGS.md is the reference you read on purpose; this is the one
-- that finds you when you have already forgotten a binding exists.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.
local wk = require('which-key')

wk.setup({
  -- Own delay, so the popup timing does not ride on 'timeoutlen' (which also
  -- governs how long a real ambiguous mapping waits).
  delay = 300,
})

-- Labels for prefixes that are not maps themselves. Everything else is picked
-- up from the `desc` on each vim.keymap.set call.
wk.add({
  { '<leader>f', group = 'find (telescope)' },
  { '<leader>d', group = 'debug (dap)' },
  { '<leader>x', group = 'diagnostics (trouble)' },
})
