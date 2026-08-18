-- nvim-treesitter (main branch): highlight/indent are opted into per buffer,
-- not via setup() — start treesitter whenever the filetype has a parser, and
-- only then hand indentation to the plugin's (experimental) indentexpr.
-- First-run bootstrap: install the everyday parsers in the background when
-- the tree-sitter CLI is present (brew: tree-sitter, required by the main
-- branch); already-installed parsers are skipped. CI/e2e opts out via
-- DOTFILES_NO_NVIM_AUTO_INSTALL.
if vim.env.DOTFILES_NO_NVIM_AUTO_INSTALL == nil and vim.fn.executable('tree-sitter') == 1 then
  require('nvim-treesitter').install({
    'bash', 'css', 'html', 'javascript', 'json', 'lua', 'markdown', 'perl',
    'python', 'ruby', 'rust', 'sql', 'toml', 'tsx', 'typescript', 'vim',
    'vimdoc', 'vue', 'yaml',
  })
end

vim.api.nvim_create_autocmd('FileType', {
  callback = function(ev)
    if pcall(vim.treesitter.start, ev.buf) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- auto close/rename HTML tags, driven by the treesitter parse tree
require('nvim-ts-autotag').setup()
