-- Auto-close brackets and quotes. check_ts makes it ask treesitter before
-- inserting, so it does not add a quote inside a string or a comment.
--
-- Loaded from init.lua's deferred block, after plugins/lsp: the cmp hookup
-- below requires cmp, and requiring it any earlier would drag the whole
-- completion stack back onto the startup path.
--
-- map_cr = false is load-bearing: autopairs maps <CR> in insert mode by
-- default, which silently overrides vim-endwise's. Measured before fixing it —
-- typing `def foo` and Enter in a .rb buffer produced no `end` at all, where
-- on main it produces one. Endwise covers every filetype it knows (ruby, lua,
-- vim, sh, ...), so it keeps <CR>; what is given up is autopairs' own smart
-- Enter, which would put a closing brace on its own line.
require('nvim-autopairs').setup({ check_ts = true, map_cr = false })

-- Without this, accepting a function completion leaves you with `foo` rather
-- than `foo()`.
require('cmp').event:on(
  'confirm_done',
  require('nvim-autopairs.completion.cmp').on_confirm_done()
)
