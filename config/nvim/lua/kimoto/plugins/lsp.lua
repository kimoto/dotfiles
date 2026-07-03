-- Native LSP stack replacing coc.nvim: mason manages server installs,
-- nvim-lspconfig supplies the per-server configs consumed by vim.lsp.config
-- (nvim 0.11+), nvim-cmp provides completion, conform runs the formatters
-- coc-prettier used to own, and the eslint language server replaces
-- coc-eslint. Builtin LSP maps (0.11+): grn=rename, gra=code action,
-- grr=references, K=hover; gd/gy/gi are added below.

require('mason').setup()
require('mason-lspconfig').setup()

-- Servers mirroring the old coc extensions. Install with :Mason (or
-- :LspInstall in a matching buffer); enabling a server that is not installed
-- yet is harmless — nvim warns once when a matching filetype is opened.
local servers = {
  'ts_ls',         -- coc-tsserver
  'eslint',        -- coc-eslint
  'pyright',       -- coc-pyright
  'solargraph',    -- coc-solargraph
  'jsonls',        -- coc-json
  'cssls',         -- coc-css
  'taplo',         -- coc-toml
  'vue_ls',        -- coc-volar
  'perlnavigator', -- coc-perl
  'sqls',          -- coc-sql
}

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
-- solargraph ships diagnostics disabled; coc-settings.json had them on.
vim.lsp.config('solargraph', {
  settings = { solargraph = { diagnostics = true } },
})
vim.lsp.enable(servers)

-- coc-settings.json parity: diagnostics as virtual text (0.11+ default: off).
vim.diagnostic.config({ virtual_text = true })

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
  end,
})

-- Format on save with prettier for the filetypes the old
-- coc.preferences.formatOnSaveFiletypes listed, falling back to the attached
-- LSP formatter for everything else conform knows nothing about.
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

-- eslint.autoFixOnSave parity: the eslint server registers LspEslintFixAll
-- per buffer on attach.
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = { '*.js', '*.jsx', '*.ts', '*.tsx', '*.vue' },
  callback = function()
    if vim.fn.exists(':LspEslintFixAll') == 2 then
      vim.cmd('LspEslintFixAll')
    end
  end,
})
