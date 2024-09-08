-- Plugin Maneger を自動でダウンロードする
local jetpackfile = vim.fn.stdpath('data') .. '/site/pack/jetpack/opt/vim-jetpack/plugin/jetpack.vim'
local jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/master/plugin/jetpack.vim"
if vim.fn.filereadable(jetpackfile) == 0 then
  vim.fn.system(string.format('curl -fsSLo %s --create-dirs %s', jetpackfile, jetpackurl))
end

-- vim-jetpack で入れ込むプラグインをここに記載していく
vim.cmd('packadd vim-jetpack')

require('jetpack.paq') {
  -- ここの中に、プラグインを追記していきます。
  {'tani/vim-jetpack', opt = 1}, -- bootstrap

  {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}, -- プラグインを読み込んだ後にコマンドを実行します。

  'kyazdani42/nvim-web-devicons',

  {'nvim-tree/nvim-tree.lua',
    requires = {
      'nvim-tree/nvim-web-devicons',
    },
  },
  'nvim-lua/plenary.nvim',
  {'nvim-telescope/telescope.nvim', tag = '0.1.8'},
  {'nvim-telescope/telescope-file-browser.nvim'},
  {"nvim-telescope/telescope-frecency.nvim", config = function() require("telescope").load_extension "frecency" end},

  'nvim-tree/nvim-web-devicons',
  {'nvim-lualine/lualine.nvim', requires = 'kyazdani42/nvim-web-devicons'},

  'yamatsum/nvim-cursorline',
  'pechorin/any-jump.vim',

  {'numToStr/Comment.nvim', config = function() require('Comment').setup() end},

  'norcalli/nvim-colorizer.lua',

  'dinhhuy258/git.nvim',

  'lewis6991/gitsigns.nvim',
  'windwp/nvim-ts-autotag',
  'pocco81/auto-save.nvim',
  'akinsho/bufferline.nvim',
  'akinsho/toggleterm.nvim',
  'echasnovski/mini.indentscope',

  -- color themes
  'Tsuzat/NeoSolarized.nvim',
  'ishan9299/nvim-solarized-lua',
  'folke/tokyonight.nvim',
  'navarasu/onedark.nvim',

  -- dev
  {'neoclide/coc.nvim', branch = 'release'},
  'farmergreg/vim-lastplace', -- 最後の編集地点に移動

  'tpope/vim-surround',
  'soramugi/auto-ctags.vim',
}
