-- Completion on Neovim's own popup menu: 'autocomplete' opens it as you type,
-- fed by the sources in 'complete' in order — the attached language server
-- (o, wired up in plugins/lsp.lua), LuaSnip snippets, file paths, then words
-- from open buffers. ⌃+Y accepts: <CR> belongs to vim-endwise.
--
-- Plugin-free at load time: LuaSnip is looked up only when a source or a key
-- runs, so this is required before the deferred plugins and the options are
-- in place for the buffers opened on the command line.
-- NOTE: keybindings here are documented in KEYBINDINGS.md (repo root).
local M = {}

local function line_to_cursor()
  return vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1)
end

-- Snippet triggers as menu items. Accepting one leaves the trigger word in
-- the buffer, and the CompleteDone below expands it in place.
function M.snippets(findstart, base)
  if findstart == 1 then
    return vim.fn.match(line_to_cursor(), [[\k*$]])
  end
  local luasnip = package.loaded.luasnip
  if not luasnip or base == '' then
    return {}
  end
  local items = {}
  for _, ft in ipairs({ vim.bo.filetype, 'all' }) do
    for _, snip in ipairs(luasnip.get_snippets(ft) or {}) do
      if not snip.hidden and vim.startswith(snip.trigger, base) then
        items[#items + 1] = {
          word = snip.trigger,
          kind = 'Snippet',
          menu = snip.name,
          user_data = { snippet = true },
        }
      end
    end
  end
  return items
end

-- Paths, relative to the working directory, once the text before the cursor
-- contains a slash; without one every word would be looked up as a file.
--
-- Items replace only the keyword under the cursor, like every other source:
-- the language server's reply redraws the whole menu from the keyword's
-- start, so an item starting earlier would have its leading `./` doubled.
local function path_before_cursor()
  return line_to_cursor():match('[%w%._~/-]*$')
end

function M.paths(findstart, base)
  if findstart == 1 then
    if not path_before_cursor():find('/') then
      return -3
    end
    return vim.fn.match(line_to_cursor(), [[\k*$]])
  end
  local path = path_before_cursor()
  local dir = path:sub(1, #path - #base)
  return vim.iter(vim.fn.getcompletion(path, 'file'))
    :filter(function(match) return vim.startswith(match, dir) end)
    :map(function(match) return { word = match:sub(#dir + 1), abbr = match, kind = 'Path' } end)
    :totable()
end

vim.o.autocomplete = true
-- popup shows the selected item's documentation beside the menu. Added here,
-- not in basic_config.lua: that file must also load on the older nvim the
-- guard test runs, which rejects the flag.
vim.opt.completeopt:append('popup')
vim.o.complete = table.concat({
  'o',
  "Fv:lua.require'kimoto.completion'.snippets",
  "Fv:lua.require'kimoto.completion'.paths",
  '.',
  'w',
  'b',
}, ',')

local group = vim.api.nvim_create_augroup('kimoto_completion', {})

vim.api.nvim_create_autocmd('CompleteDone', {
  group = group,
  callback = function()
    local user_data = vim.v.completed_item.user_data
    if vim.v.event.reason == 'accept' and type(user_data) == 'table' and user_data.snippet then
      vim.schedule(function() require('luasnip').expand() end)
    end
  end,
})

-- Telescope's prompt is an insert-mode buffer too; a menu there would cover
-- the results being filtered.
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].buftype == 'prompt' then
      vim.bo[ev.buf].autocomplete = false
    end
  end,
})

vim.keymap.set('i', '<C-Space>', function() vim.lsp.completion.get() end,
  { desc = 'Ask the language server for completions' })

-- Tab moves between a snippet's placeholders — LuaSnip's, or vim.snippet's
-- for a snippet a language server sent — and is a plain Tab everywhere else.
local function jump(dir)
  return function()
    local luasnip = package.loaded.luasnip
    if luasnip and luasnip.locally_jumpable(dir) then
      luasnip.jump(dir)
    elseif vim.snippet.active({ direction = dir }) then
      vim.snippet.jump(dir)
    else
      vim.api.nvim_feedkeys(vim.keycode(dir == 1 and '<Tab>' or '<S-Tab>'), 'n', false)
    end
  end
end
vim.keymap.set({ 'i', 's' }, '<Tab>', jump(1), { desc = 'Next snippet placeholder' })
vim.keymap.set({ 'i', 's' }, '<S-Tab>', jump(-1), { desc = 'Previous snippet placeholder' })

return M
