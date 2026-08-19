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

-- Completion: LSP/buffer/path sources plus snippets.
--
-- LuaSnip rather than the builtin vim.snippet: the builtin only expands
-- snippets a language server sends back, so there were no standalone snippets
-- at all. friendly-snippets supplies the bodies (lazy_load reads only the
-- packs for filetypes actually opened) and cmp_luasnip surfaces them as a
-- completion source.
local cmp = require('cmp')
local luasnip = require('luasnip')
require('luasnip.loaders.from_vscode').lazy_load()

cmp.setup({
  snippet = {
    expand = function(args) luasnip.lsp_expand(args.body) end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>'] = cmp.mapping.confirm({ select = false }),
    -- Tab moves between a snippet's placeholders and is a plain Tab
    -- everywhere else, so nothing is taken away when no snippet is active.
    ['<Tab>'] = cmp.mapping(function(fallback)
      if luasnip.locally_jumpable(1) then luasnip.jump(1) else fallback() end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if luasnip.locally_jumpable(-1) then luasnip.jump(-1) else fallback() end
    end, { 'i', 's' }),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
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
    local function map(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = ev.buf, desc = desc })
    end
    map('gd', vim.lsp.buf.definition, 'LSP: definition')
    map('gy', vim.lsp.buf.type_definition, 'LSP: type definition')
    map('gi', vim.lsp.buf.implementation, 'LSP: implementation')
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
