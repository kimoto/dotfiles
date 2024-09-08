-- Plugin Maneger を自動でダウンロードする
local jetpackfile = vim.fn.stdpath('data') .. '/site/pack/jetpack/opt/vim-jetpack/plugin/jetpack.vim'
local jetpackurl = "https://raw.githubusercontent.com/tani/vim-jetpack/master/plugin/jetpack.vim"
if vim.fn.filereadable(jetpackfile) == 0 then
  vim.fn.system(string.format('curl -fsSLo %s --create-dirs %s', jetpackfile, jetpackurl))
end

vim.cmd('packadd vim-jetpack')

require('jetpack.paq') {
  {'tani/vim-jetpack', opt = 1}, -- bootstrap

  {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'},
  'tpope/vim-endwise', -- Rubyのendなどの自動補完

  'nvim-tree/nvim-web-devicons',
  {'nvim-tree/nvim-tree.lua', -- treesitter
    requires = {
      'nvim-tree/nvim-web-devicons',
    },
  },

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

  'norcalli/nvim-colorizer.lua', -- カーソル下と同じ単語を強調

  'dinhhuy258/git.nvim', -- like fugitive.vim
  'lewis6991/gitsigns.nvim', -- git statusを表示

  'windwp/nvim-ts-autotag', -- tagsの自動生成
  'pocco81/auto-save.nvim', -- 自動保存

  'akinsho/bufferline.nvim',
  'akinsho/toggleterm.nvim',

  -- color themes
  'Tsuzat/NeoSolarized.nvim',
  'ishan9299/nvim-solarized-lua',
  'folke/tokyonight.nvim',
  'navarasu/onedark.nvim',

  -- dev
  {'neoclide/coc.nvim', branch = 'release'},
  'farmergreg/vim-lastplace', -- 最後の編集地点に移動

  'tpope/vim-surround', -- text objectの拡張
  -- 'soramugi/auto-ctags.vim',
  -- 'hiphish/rainbow-delimiters.nvim' -- rainbow brackets
}
