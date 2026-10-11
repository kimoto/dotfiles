-- Plugins are managed by Neovim's built-in vim.pack. A missing plugin is
-- cloned on startup, at the revision pinned in nvim-pack-lock.json (committed
-- next to init.lua). Update with `:lua vim.pack.update()`, review, `:write`,
-- then commit the lockfile.
local gh = function(repo) return 'https://github.com/' .. repo end

-- vim-jetpack's plugin tree is also on the packpath, and :packadd loads every
-- match, so a machine that still has it would load two copies of each plugin.
local jetpack_dir = vim.fn.stdpath('data') .. '/site/pack/jetpack'
if vim.uv.fs_stat(jetpack_dir) then
  vim.fs.rm(jetpack_dir, { recursive = true, force = true })
end

vim.pack.add({
  -- shared dependencies, declared before the plugins that pull them in
  gh('nvim-lua/plenary.nvim'),
  gh('nvim-tree/nvim-web-devicons'),

  -- main branch: parsers are managed via require('nvim-treesitter').install()
  -- (see plugins/treesitter.lua), so no :TSUpdate run-hook.
  { src = gh('nvim-treesitter/nvim-treesitter'), version = 'main' },
  gh('windwp/nvim-ts-autotag'), -- auto close/rename HTML tags (treesitter-based)

  -- ui
  gh('nvim-tree/nvim-tree.lua'), -- file explorer
  gh('nvim-lualine/lualine.nvim'),
  gh('akinsho/bufferline.nvim'),
  gh('akinsho/toggleterm.nvim'),
  gh('yamatsum/nvim-cursorline'),
  gh('folke/which-key.nvim'), -- popup listing the keys behind a prefix
  gh('folke/trouble.nvim'), -- list every diagnostic instead of one line at a time
  gh('NvChad/nvim-colorizer.lua'), -- highlight color codes like #rrggbb
  gh('navarasu/onedark.nvim'), -- color theme

  -- telescope
  { src = gh('nvim-telescope/telescope.nvim'), version = '0.1.8' },
  gh('nvim-telescope/telescope-frecency.nvim'),

  -- editing
  gh('gbprod/yanky.nvim'), -- yank ring
  gh('numToStr/Comment.nvim'),
  gh('pocco81/auto-save.nvim'), -- 自動保存
  gh('windwp/nvim-autopairs'), -- 括弧・クォートの自動閉じ
  gh('tpope/vim-surround'), -- text objectの拡張
  gh('tpope/vim-endwise'), -- Rubyのendなどの自動補完
  gh('farmergreg/vim-lastplace'), -- 最後の編集地点に移動
  gh('pechorin/any-jump.vim'), -- grep-based jump to definition

  gh('lewis6991/gitsigns.nvim'), -- git statusを表示

  -- lsp / completion / formatting
  gh('neovim/nvim-lspconfig'),        -- per-server configs for vim.lsp.config
  gh('mason-org/mason.nvim'),         -- language server installer (:Mason)
  gh('mason-org/mason-lspconfig.nvim'),
  gh('hrsh7th/nvim-cmp'),             -- completion
  gh('hrsh7th/cmp-nvim-lsp'),
  gh('hrsh7th/cmp-buffer'),
  gh('hrsh7th/cmp-path'),
  gh('stevearc/conform.nvim'),        -- format on save (prettier etc.)
  gh('L3MON4D3/LuaSnip'),             -- snippet engine
  gh('saadparwaiz1/cmp_luasnip'),     -- its cmp source
  gh('rafamadriz/friendly-snippets'), -- the snippet bodies themselves (vscode format)

  -- debugger (nvim-dap)
  gh('mfussenegger/nvim-dap'),
  gh('nvim-neotest/nvim-nio'),
  gh('rcarriga/nvim-dap-ui'),
  gh('mfussenegger/nvim-dap-python'),
  gh('suketa/nvim-dap-ruby'),
}, { confirm = false })

-- A plugin dropped from the list above stays on disk (and in the lockfile)
-- until vim.pack.del removes it, so remove whatever this session did not add.
local stale = vim.iter(vim.pack.get())
  :filter(function(p) return not p.active end)
  :map(function(p) return p.spec.name end)
  :totable()
if #stale > 0 then
  vim.pack.del(stale)
end

require('telescope').load_extension('frecency')
require('Comment').setup()
