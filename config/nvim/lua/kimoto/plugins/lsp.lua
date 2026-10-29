-- Native LSP stack: Homebrew installs the servers, nvim-lspconfig supplies the
-- per-server configs consumed by vim.lsp.config (nvim 0.11+), the builtin
-- completion menu shows their items (see kimoto/completion.lua), and conform
-- runs the formatters. Builtin LSP maps (0.11+):
-- grn=rename, gra=code action, grr=references, K=hover; gd/gy/gi are added below.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root) —
-- update it when adding or changing a map.

-- The servers come from Brewfile.extra, so they update through the same
-- reviewed path as every other tool; nothing is downloaded when nvim starts.
-- sqls has no formula: `:MasonInstall sqls` by hand where it is wanted.
-- Enabling a server that is not installed is harmless — nvim warns once when
-- a matching filetype is opened.
local servers = {
  'bashls',        -- sh / bash; diagnostics come from shellcheck
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

-- Appended, so a server Homebrew provides wins over a copy Mason installed.
require('mason').setup({ PATH = 'append' })

-- Snippets for the completion menu (kimoto/completion.lua lists them).
--
-- LuaSnip rather than the builtin vim.snippet: the builtin only expands
-- snippets a language server sends back, so there were no standalone snippets
-- at all. friendly-snippets supplies the bodies; lazy_load reads only the
-- packs for filetypes actually opened.
require('luasnip')
require('luasnip.loaders.from_vscode').lazy_load()

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

    -- Items reach the menu through 'omnifunc' (the `o` in 'complete');
    -- enabling also applies what accepting an item implies — expanding its
    -- snippet, adding its import.
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, ev.buf)
    end
  end,
})

-- Format on save with prettier for the filetypes it handles, falling back to
-- the attached LSP formatter for everything else.
--
-- format_after_save, not format_on_save: the sync variant runs prettier
-- *before* the write completes, and auto-save (plugins/auto_save.lua) writes on
-- every InsertLeave — so leaving insert mode in a js/ts/json/css/html/md/yaml
-- buffer froze the editor for the length of a node startup. Measured here with
-- prettier 3.9.6: 299ms on the first write, 257ms on a write of an
-- already-formatted buffer (the cost is spawning node, not the diff). Async it
-- is 12ms. Verified alongside that: :wq still leaves a formatted file on disk
-- (conform waits on exit), and a format whose buffer changed while it ran is
-- dropped rather than applied, so it cannot clobber what you typed after Esc.
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
  format_after_save = { lsp_format = 'fallback' },
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
