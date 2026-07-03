-- Plugin Maneger を自動でダウンロードする
local jetpackfile = vim.fn.stdpath('data') .. '/site/pack/jetpack/opt/vim-jetpack/plugin/jetpack.vim'
local jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/master/plugin/jetpack.vim"
if vim.fn.filereadable(jetpackfile) == 0 then
  vim.fn.system(string.format('curl -fsSLo %s --create-dirs %s', jetpackfile, jetpackurl))
end

-- Neovim 0.12+ defines vim.list as a table module; the upstream jetpack.vim
-- uses `local list = vim.list or function...` which picks up the table and
-- then fails when cast() tries to call it. Patch the assignment to guard with
-- type() so the fallback identity function is used instead.
local lines = vim.fn.readfile(jetpackfile)
local patched = false
for i, line in ipairs(lines) do
  local new_line, n = line:gsub(
    'local list = vim%.list or function',
    'local list = type(vim.list) == "function" and vim.list or function'
  )
  if n > 0 then
    lines[i] = new_line
    patched = true
  end
end
-- Write back only when the patch actually applied, so an already-patched file
-- isn't rewritten on every startup.
if patched then
  vim.fn.writefile(lines, jetpackfile)
end

vim.cmd('packadd vim-jetpack')

require('jetpack.paq') {
  {'tani/vim-jetpack', opt = 1}, -- bootstrap

  {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'},

  'nvim-tree/nvim-web-devicons',
  {'nvim-tree/nvim-tree.lua', -- file explorer
    requires = {
      'nvim-tree/nvim-web-devicons',
    },
  },

  {"gbprod/yanky.nvim"},

  -- telescope
  'nvim-lua/plenary.nvim',
  {'nvim-telescope/telescope.nvim', tag = '0.1.8'},
  {'nvim-telescope/telescope-file-browser.nvim'},
  {"nvim-telescope/telescope-frecency.nvim", config = function() require("telescope").load_extension "frecency" end},

  -- lualine
  {'nvim-lualine/lualine.nvim', requires = 'nvim-tree/nvim-web-devicons'},

  'yamatsum/nvim-cursorline',
  'pechorin/any-jump.vim',

  {'numToStr/Comment.nvim', config = function() require('Comment').setup() end},

  'NvChad/nvim-colorizer.lua', -- highlight color codes like #rrggbb

  'lewis6991/gitsigns.nvim', -- git statusを表示
  {'kdheepak/lazygit.nvim', requires = 'nvim-lua/plenary.nvim'},

  'windwp/nvim-ts-autotag', -- auto close/rename HTML tags (treesitter-based)
  'pocco81/auto-save.nvim', -- 自動保存

  'akinsho/bufferline.nvim',
  'akinsho/toggleterm.nvim',

  -- color themes
  'navarasu/onedark.nvim',

  -- dev: native LSP stack (replaces coc.nvim)
  'neovim/nvim-lspconfig',        -- per-server configs for vim.lsp.config
  'mason-org/mason.nvim',         -- language server installer (:Mason)
  'mason-org/mason-lspconfig.nvim',
  'hrsh7th/nvim-cmp',             -- completion
  'hrsh7th/cmp-nvim-lsp',
  'hrsh7th/cmp-buffer',
  'hrsh7th/cmp-path',
  'stevearc/conform.nvim',        -- format on save (prettier etc.)

  'farmergreg/vim-lastplace', -- 最後の編集地点に移動

  'tpope/vim-surround', -- text objectの拡張

  -- lang
  'tpope/vim-endwise', -- Rubyのendなどの自動補完
  'rust-lang/rust.vim', -- Rust

  'sindrets/diffview.nvim', -- for git mergetool

  -- debugger
  ---- base
  'mfussenegger/nvim-dap',
  'nvim-neotest/nvim-nio',
  'rcarriga/nvim-dap-ui',
  -- python
  'https://github.com/mfussenegger/nvim-dap-python',
  -- ruby
  'suketa/nvim-dap-ruby',
}
