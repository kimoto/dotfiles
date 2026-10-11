-- Plugins are managed by Neovim's built-in vim.pack. On startup every plugin
-- is cloned or moved to the revision pinned in nvim-pack-lock.json (committed
-- next to init.lua), so a pulled lockfile needs nothing run by hand. Update with `:lua vim.pack.update()`, review, `:write`,
-- then commit the lockfile.
local gh = function(repo) return 'https://github.com/' .. repo end

-- vim-jetpack's plugin tree is also on the packpath, and :packadd loads every
-- match, so a machine that still has it would load two copies of each plugin.
local jetpack_dir = vim.fn.stdpath('data') .. '/site/pack/jetpack'
if vim.uv.fs_stat(jetpack_dir) then
  vim.fs.rm(jetpack_dir, { recursive = true, force = true })
end

-- vim.pack.add never revisits a plugin already on disk, so a lockfile pulled
-- from another machine would otherwise be ignored until someone updated by
-- hand. Move every plugin whose checkout differs from its locked revision
-- before anything loads. Reads .git/HEAD directly: no git process per plugin.
local function checked_out(path)
  local f = io.open(path .. '/.git/HEAD')
  if not f then return nil end
  local head = f:read('*l')
  f:close()
  return head
end
local drifted = vim.iter(vim.pack.get(nil, { info = false }))
  :filter(function(p)
    local head = checked_out(p.path)
    return head ~= nil and head:match('^%x+$') ~= nil and head ~= p.rev
  end)
  :map(function(p) return p.spec.name end)
  :totable()
if #drifted > 0 then
  vim.pack.update(drifted, { target = 'lockfile', force = true })
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
  -- 0.2+: 0.1.x calls nvim-treesitter APIs its main branch no longer has
  { src = gh('nvim-telescope/telescope.nvim'), version = vim.version.range('0.2') },
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
  gh('stevearc/conform.nvim'),        -- format on save (prettier etc.)
  gh('L3MON4D3/LuaSnip'),             -- snippet engine
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
