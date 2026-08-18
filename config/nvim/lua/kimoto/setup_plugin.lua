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

  -- shared dependencies, declared before the plugins that pull them in
  'nvim-lua/plenary.nvim',
  'nvim-tree/nvim-web-devicons',

  -- main branch: parsers are managed via require('nvim-treesitter').install()
  -- (see plugins/treesitter.lua), so no :TSUpdate run-hook.
  'nvim-treesitter/nvim-treesitter',
  'windwp/nvim-ts-autotag', -- auto close/rename HTML tags (treesitter-based)

  -- ui
  'nvim-tree/nvim-tree.lua', -- file explorer
  'nvim-lualine/lualine.nvim',
  'akinsho/bufferline.nvim',
  'akinsho/toggleterm.nvim',
  'yamatsum/nvim-cursorline',
  'NvChad/nvim-colorizer.lua', -- highlight color codes like #rrggbb
  'navarasu/onedark.nvim', -- color theme

  -- telescope
  {'nvim-telescope/telescope.nvim', tag = '0.1.8'},
  {'nvim-telescope/telescope-frecency.nvim',
    config = function() require('telescope').load_extension 'frecency' end,
  },

  -- editing
  'gbprod/yanky.nvim', -- yank ring
  {'numToStr/Comment.nvim', config = function() require('Comment').setup() end},
  'pocco81/auto-save.nvim', -- 自動保存
  'tpope/vim-surround', -- text objectの拡張
  'tpope/vim-endwise', -- Rubyのendなどの自動補完
  'farmergreg/vim-lastplace', -- 最後の編集地点に移動
  'pechorin/any-jump.vim', -- grep-based jump to definition

  'lewis6991/gitsigns.nvim', -- git statusを表示

  -- lsp / completion / formatting
  'neovim/nvim-lspconfig',        -- per-server configs for vim.lsp.config
  'mason-org/mason.nvim',         -- language server installer (:Mason)
  'mason-org/mason-lspconfig.nvim',
  'hrsh7th/nvim-cmp',             -- completion
  'hrsh7th/cmp-nvim-lsp',
  'hrsh7th/cmp-buffer',
  'hrsh7th/cmp-path',
  'stevearc/conform.nvim',        -- format on save (prettier etc.)

  -- debugger (nvim-dap)
  'mfussenegger/nvim-dap',
  'nvim-neotest/nvim-nio',
  'rcarriga/nvim-dap-ui',
  'mfussenegger/nvim-dap-python',
  'suketa/nvim-dap-ruby',
}

-- Bootstrap: run JetpackSync (blocking) whenever what is on disk no longer
-- matches the list above, instead of leaving every require erroring — or
-- jetpack's "Some packages are not synchronized" nag on every startup — until
-- someone runs it by hand.
local function out_of_sync()
  -- Declared but not installed: jetpack#tap() is false for those.
  local declared = vim.fn['jetpack#names']()
  for _, name in ipairs(declared) do
    if vim.fn['jetpack#tap'](name) == 0 then
      return true
    end
  end
  -- Installed but no longer declared: jetpack records what it installed in
  -- available_packages.json next to the package tree.
  local manifest = vim.fn.stdpath('data') .. '/site/pack/jetpack/opt/available_packages.json'
  local ok, available = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(manifest), '\n'))
  end)
  if not ok or type(available) ~= 'table' then
    return false
  end
  local is_declared = {}
  for _, name in ipairs(declared) do
    is_declared[name] = true
  end
  for name in pairs(available) do
    if not is_declared[name] then
      return true
    end
  end
  return false
end

if out_of_sync() then
  vim.notify('[dotfiles] syncing plugins (JetpackSync) ...')
  local ok, err = pcall(vim.cmd, 'JetpackSync')
  if ok then
    vim.notify('[dotfiles] plugin sync finished — restart nvim if anything looks off')
  else
    vim.notify('[dotfiles] JetpackSync failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end
