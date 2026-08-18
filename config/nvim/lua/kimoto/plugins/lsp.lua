-- Native LSP stack: mason manages server installs, nvim-lspconfig supplies the
-- per-server configs consumed by vim.lsp.config (nvim 0.11+), nvim-cmp provides
-- completion, and conform runs the formatters. Builtin LSP maps (0.11+):
-- grn=rename, gra=code action, grr=references, K=hover; gd/gy/gi are added below.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.

-- mason-lspconfig auto-installs missing servers on startup (first-run
-- bootstrap); enabling a server that is not installed yet is harmless — nvim
-- warns once when a matching filetype is opened. CI/e2e sets
-- DOTFILES_NO_NVIM_AUTO_INSTALL to keep startups deterministic (no background
-- downloads while assertions run).
local servers = {
  'ts_ls',         -- typescript / javascript
  'eslint',
  'pyright',       -- python
  'solargraph',    -- ruby
  'jsonls',
  'cssls',
  'taplo',         -- toml
  'vue_ls',
  'perlnavigator', -- perl
  'sqls',          -- sql
}

require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = vim.env.DOTFILES_NO_NVIM_AUTO_INSTALL == nil and servers or {},
})

-- Completion: LSP/buffer/path sources, snippets via the builtin vim.snippet.
local cmp = require('cmp')
cmp.setup({
  snippet = {
    expand = function(args) vim.snippet.expand(args.body) end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>'] = cmp.mapping.confirm({ select = false }),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
  }, {
    { name = 'buffer' },
    { name = 'path' },
  }),
})

vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})
-- solargraph ships with diagnostics off; turn them on.
vim.lsp.config('solargraph', {
  settings = { solargraph = { diagnostics = true } },
})
vim.lsp.enable(servers)

-- Diagnostics as virtual text (0.11+ default: off).
vim.diagnostic.config({ virtual_text = true })

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
  end,
})

-- Format on save with prettier for the filetypes it handles, falling back to
-- the attached LSP formatter for everything else.
require('conform').setup({
  formatters_by_ft = {
    javascript = { 'prettier' },
    javascriptreact = { 'prettier' },
    typescript = { 'prettier' },
    typescriptreact = { 'prettier' },
    vue = { 'prettier' },
    json = { 'prettier' },
    jsonc = { 'prettier' },
    css = { 'prettier' },
    html = { 'prettier' },
    markdown = { 'prettier' },
    yaml = { 'prettier' },
    graphql = { 'prettier' },
    handlebars = { 'prettier' },
  },
  format_on_save = { timeout_ms = 1000, lsp_format = 'fallback' },
})

-- Auto-fix eslint findings on write. The eslint server registers
-- LspEslintFixAll per buffer on attach, so the command only exists where it
-- has actually attached.
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = { '*.js', '*.jsx', '*.ts', '*.tsx', '*.vue' },
  callback = function()
    if vim.fn.exists(':LspEslintFixAll') == 2 then
      vim.cmd('LspEslintFixAll')
    end
  end,
})
