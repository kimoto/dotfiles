-- Auto-close brackets and quotes. check_ts makes it ask treesitter before
-- inserting, so it does not add a quote inside a string or a comment.
--
-- map_cr = false is load-bearing: autopairs maps <CR> in insert mode by
-- default, which silently overrides vim-endwise's. Measured before fixing it —
-- typing `def foo` and Enter in a .rb buffer produced no `end` at all, where
-- on main it produces one. Endwise covers every filetype it knows (ruby, lua,
-- vim, sh, ...), so it keeps <CR>; what is given up is autopairs' own smart
-- Enter, which would put a closing brace on its own line.
require('nvim-autopairs').setup({ check_ts = true, map_cr = false })
