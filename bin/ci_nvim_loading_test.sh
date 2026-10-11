#!/bin/bash
# End-to-end test for the Neovim config (config/nvim): let a first startup
# install every declared plugin through vim.pack, exactly as on a fresh
# machine, then assert a full init.lua startup is clean.
#
# This is the nvim analogue of ci_vim_loading_test.sh and the layer above
# ci_nvim_guard_test.sh (which loads only the plugin-free basic_config.lua).
# It needs the network (one clone per plugin), so it
# runs as its own CI job with the installed plugin tree cached, instead of
# inside the hermetic per-push guard.
#
# Set NVIM_E2E_DATA_DIR to a persistent directory to reuse the installed
# plugin tree across runs (the CI job caches it); otherwise everything lives
# in a throwaway tempdir.
#
# Network note: in a restricted sandbox where github.com is only reachable for
# the in-scope repo via a git relay, run with GIT_CONFIG_GLOBAL=/dev/null so
# the plugin clones use plain HTTPS. On GitHub Actions (open network) it's a
# no-op.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew nvim (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v nvim >/dev/null 2>&1 || die "nvim not installed"
command -v git  >/dev/null 2>&1 || die "git not installed"
command -v tmux >/dev/null 2>&1 || die "tmux not installed"
command -v python3 >/dev/null 2>&1 || die "python3 not installed (needed by the stub LSP server)"
REPO="$PWD"
[ -f "$REPO/config/nvim/init.lua" ] || die "no config/nvim/init.lua in $REPO"
echo "== $(nvim --version | head -1) =="

HOME_DIR="$(mktemp -d)"
SOCK="ci_nvim_e2e_$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$HOME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Isolated HOME + XDG dirs; the repo config is linked in the same shape mklink
# produces (~/.config -> config/). Only XDG_DATA_HOME (the plugin clones)
# is optionally persistent so CI can cache it across runs.
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="${NVIM_E2E_DATA_DIR:-$HOME_DIR/.local/share}"
export XDG_STATE_HOME="$HOME_DIR/.local/state"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
ln -s "$REPO/config/nvim" "$XDG_CONFIG_HOME/nvim"

# Keep startups deterministic: the config's first-run auto-installers (mason
# servers, treesitter parsers) must not kick off background downloads while
# the assertions below read :messages / the rendered screen. The vim.pack
# plugin install itself is NOT gated by this — phase 1 relies on it.
export DOTFILES_NO_NVIM_AUTO_INSTALL=1

run_nvim() { HOME="$HOME_DIR" nvim --headless "$@" </dev/null; }

# Write a g:clipboard provider that copies to / pastes from a plain file. Used
# both to silence tmux's clipboard in the pane and to assert that a yank
# actually leaves nvim. It has to be loaded with --cmd: g:clipboard is read
# when the provider is first resolved, which can happen before a -c command.
write_clipboard_provider() {
  local lua_file="$1" store="$2"
  cat >"$lua_file" <<PROVIDER
local copy = { 'sh', '-c', 'cat > $store' }
local paste = { 'sh', '-c', 'cat $store 2>/dev/null' }
vim.g.clipboard = {
  name = 'stub',
  copy = { ['+'] = copy, ['*'] = copy },
  paste = { ['+'] = paste, ['*'] = paste },
  cache_enabled = 0,
}
PROVIDER
}

# ---------------------------------------------------------------------------
# Install: a plain first startup must bootstrap everything on its own —
# vim.pack.add in setup_plugin.lua clones every missing plugin at the
# lockfile's revision (no manual sync). Errors from init.lua are tolerated on
# this run — the per-plugin requires can fire before the install finishes — so this
# phase only has to leave a complete plugin tree behind; correctness of the
# config is asserted by the startup checks below.
# ---------------------------------------------------------------------------
echo "== first-run bootstrap (plain startup must auto-install plugins) =="
# A vim-jetpack tree left on the packpath would be loaded next to vim.pack's
# copies, so the first startup must delete it.
JETPACK_DIR="$XDG_DATA_HOME/nvim/site/pack/jetpack"
mkdir -p "$JETPACK_DIR/opt/telescope.nvim/plugin"
sync_log="$HOME_DIR/sync.log"
run_nvim -c 'qall!' >"$sync_log" 2>&1 || {
  cat "$sync_log"; die "first-run bootstrap exited non-zero"; }
tail -n 20 "$sync_log"

# A failed clone is only a notification, so verify the end state directly:
# representative plugins must exist in vim.pack's directory.
PACK_DIR="$XDG_DATA_HOME/nvim/site/pack/core/opt"
[ -d "$PACK_DIR" ] || die "vim.pack dir missing after install ($PACK_DIR)"
for p in telescope.nvim nvim-tree.lua mason.nvim LuaSnip onedark.nvim nvim-treesitter; do
  [ -d "$PACK_DIR/$p" ] || die "plugin $p not installed under $PACK_DIR (clone failed?)"
done
[ ! -e "$JETPACK_DIR" ] || die "vim-jetpack tree survived startup ($JETPACK_DIR)"
echo "== plugin tree present, jetpack tree gone =="

# A lockfile pulled from another machine pins revisions the plugins on disk
# are not at; the next startup must move them there with nothing run by hand.
echo "== lockfile follow check =="
LOCKED_REV=$(python3 -c 'import json, sys; print(json.load(sys.stdin)["plugins"]["telescope.nvim"]["rev"])' \
  <"$REPO/config/nvim/nvim-pack-lock.json")
TELESCOPE_DIR="$PACK_DIR/telescope.nvim"
git -C "$TELESCOPE_DIR" checkout -q --detach HEAD~1
[ "$(git -C "$TELESCOPE_DIR" rev-parse HEAD)" != "$LOCKED_REV" ] ||
  die "could not move telescope.nvim off its locked revision"
run_nvim -c 'qall!' >"$HOME_DIR/follow.log" 2>&1 || {
  cat "$HOME_DIR/follow.log"; die "startup after a lockfile change exited non-zero"; }
[ "$(git -C "$TELESCOPE_DIR" rev-parse HEAD)" = "$LOCKED_REV" ] ||
  die "startup left telescope.nvim off the lockfile's revision $LOCKED_REV"
echo "== startup moved the plugin to the lockfile's revision =="

# ---------------------------------------------------------------------------
# Assert 1 (headless): a full init.lua startup produces no error messages and
# representative plugins really loaded — commands defined, colorscheme
# applied, lualine required, yanky mappings active.
# ---------------------------------------------------------------------------
echo "== headless startup check =="
msgs="$HOME_DIR/messages.txt"
startup_log="$HOME_DIR/startup.log"
# The probes go through a sourced file, not one -c per probe: nvim rejects
# more than 10 "-c command" arguments outright.
probe="$HOME_DIR/probe.vim"
cat >"$probe" <<PROBE
set nomore
redir! > $msgs
silent messages
silent echo "TELESCOPE=".(exists(":Telescope")?"loaded":"missing")
lua _G.tp_ok = pcall(require('telescope.previewers.utils').highlighter, vim.api.nvim_create_buf(false, true), 'lua')
silent echo "TELESCOPE_PREVIEW=".(luaeval("_G.tp_ok")?"ok":"error")
silent echo "NVIMTREE=".(exists(":NvimTreeToggle")?"loaded":"missing")
silent echo "TOGGLETERM=".(exists(":ToggleTerm")?"loaded":"missing")
silent echo "TREESITTER=".(exists(":TSUpdate")?"loaded":"missing")
silent echo "MASON=".(exists(":Mason")?"loaded":"missing")
silent echo "LUASNIP=".(luaeval("package.loaded['luasnip'] ~= nil")?"loaded":"missing")
silent echo "CONFORM=".(luaeval("package.loaded['conform'] ~= nil")?"loaded":"missing")
silent echo "CONFORM_PRE=".luaeval("#vim.api.nvim_get_autocmds({group='Conform',event='BufWritePre'})")
silent echo "CONFORM_POST=".luaeval("#vim.api.nvim_get_autocmds({group='Conform',event='BufWritePost'})")
silent echo "LSP_TS=".(luaeval("vim.lsp.config['ts_ls'] ~= nil")?"configured":"missing")
silent echo "LSP_TS_ENABLED=".(luaeval("vim.lsp.is_enabled('ts_ls')")?"yes":"no")
silent echo "COLORSCHEME=".(exists("g:colors_name")?g:colors_name:"none")
silent echo "LUALINE=".(luaeval("package.loaded['lualine'] ~= nil")?"loaded":"missing")
silent echo "YANKY_P=".(maparg("p","n")=~#"Yanky"?"mapped":"missing")
silent echo "WHICHKEY=".(exists(":WhichKey")?"loaded":"missing")
silent echo "WHICHKEY_CFG=".(luaeval("package.loaded['kimoto/plugins/which_key'] ~= nil")?"loaded":"missing")
silent echo "DESC_FF=".(get(maparg("<leader>ff","n",0,1),"desc","none"))
silent echo "DESC_FL=".(get(maparg("<leader>fl","n",0,1),"desc","none"))
silent echo "DESC_DAPUI=".(get(maparg("<leader>du","n",0,1),"desc","none"))
redir END
qall!
PROBE
# Sourced from VimEnter, not straight from -c: init.lua defers the LSP/DAP
# modules to a VimEnter autocmd, so a -c probe that waits would spin the event
# loop first and read a state the real editor never sits in. The sleep then
# lets just-after-startup async work surface errors before :messages is dumped.
run_nvim -c "autocmd VimEnter * ++once sleep 800m | source $probe" >"$startup_log" 2>&1 || {
  echo "---- startup output ----"; cat "$startup_log"
  die "nvim exited non-zero on startup"; }

echo "---- :messages ----"; cat "$msgs"; echo "-------------------"
if grep -nE "E[0-9]{2,}:|Error detected|Unknown function|module '.*' not found|attempt to" "$msgs"; then
  die "startup produced errors (see :messages above)"
fi
grep -q "TELESCOPE=loaded"    "$msgs" || die "telescope did not load"
# The previewer highlights through nvim-treesitter, whose main branch dropped
# APIs older telescope releases call; this fails only once a preview opens.
grep -q "TELESCOPE_PREVIEW=ok" "$msgs" || die "telescope's previewer cannot highlight a buffer"
grep -q "NVIMTREE=loaded"     "$msgs" || die "nvim-tree did not load"
grep -q "TOGGLETERM=loaded"   "$msgs" || die "toggleterm did not load"
grep -q "TREESITTER=loaded"   "$msgs" || die "nvim-treesitter did not load"
grep -q "MASON=loaded"        "$msgs" || die "mason did not load"
grep -q "LUASNIP=loaded"      "$msgs" || die "LuaSnip did not load"
grep -q "CONFORM=loaded"      "$msgs" || die "conform did not load"
# conform hooks BufWritePre when it formats synchronously and BufWritePost
# when it formats after the write. auto-save writes on every InsertLeave, so
# the sync variant froze the editor for a node startup (~260ms measured)
# every time you left insert mode in a prettier filetype.
grep -q "CONFORM_POST=1" "$msgs" ||
  die "conform is not formatting after the write (format_after_save gone)"
grep -q "CONFORM_PRE=0"  "$msgs" ||
  die "conform formats before the write again — every auto-save now blocks on prettier"
grep -q "LSP_TS=configured"   "$msgs" || die "ts_ls lsp config not resolved"
# lspconfig resolves vim.lsp.config[...] on its own, so the line above passes
# even if plugins/lsp.lua never ran. is_enabled() is true only because that
# module called vim.lsp.enable() — the part that startup deferral could break.
grep -q "LSP_TS_ENABLED=yes" "$msgs" || die "vim.lsp.enable() never ran (plugins/lsp.lua did not load)"
grep -q "COLORSCHEME=onedark" "$msgs" || die "onedark colorscheme not applied"
grep -q "LUALINE=loaded"      "$msgs" || die "lualine did not load"
grep -q "YANKY_P=mapped"      "$msgs" || die "yanky put mapping not active"
grep -q "WHICHKEY=loaded"     "$msgs" || die "which-key plugin did not load"
# The plugin ships its own plugin/ file, so ":WhichKey existing" alone would
# pass even with our module gone — assert our config module ran too.
grep -q "WHICHKEY_CFG=loaded" "$msgs" || die "kimoto/plugins/which_key was not required from init.lua"
# which-key renders whatever `desc` each map carries, so a map registered
# without one is invisible in the popup even though the key still works.
grep -q "DESC_FF=Find files"  "$msgs" || die "<leader>ff has no desc (which-key would show it blank)"
grep -q "DESC_FL=Reopen the last picker" "$msgs" ||
  die "<leader>fl (telescope resume) is missing"
grep -q "DESC_DAPUI=Debug: toggle dap-ui" "$msgs" ||
  die "<leader>du missing/undescribed (dap-ui toggle must not sit on the <leader>d prefix)"
echo "== headless startup clean (no errors, plugins + colorscheme loaded) =="

# ---------------------------------------------------------------------------
# Assert 2 (real terminal): drive nvim in a real tmux pane and confirm it
# lands on a normal editing screen — lualine rendered, no error wall and no
# blocking "Press ENTER" prompt (the classic broken-config symptom that a
# headless run can miss for UI-time errors).
# ---------------------------------------------------------------------------
echo "== real-terminal startup check =="
# The config sets clipboard=unnamedplus, and inside a detached tmux session
# nvim's provider auto-detection picks tmux and then fails with "no current
# client" — noise that lands on the message line and can swallow a keypress.
# Give this nvim the stub provider so the pane only shows real problems; the
# clipboard itself is asserted properly further down.
write_clipboard_provider "$HOME_DIR/tmux_clipboard.lua" "$HOME_DIR/tmux_clipboard.txt"
tmux -L "$SOCK" new-session -d -x 180 -y 45 \
  "env HOME='$HOME_DIR' XDG_CONFIG_HOME='$XDG_CONFIG_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' \
       XDG_STATE_HOME='$XDG_STATE_HOME' XDG_CACHE_HOME='$XDG_CACHE_HOME' \
       TERM=xterm-256color nvim --cmd 'luafile $HOME_DIR/tmux_clipboard.lua'" ||
  die "failed to start tmux session"

screen=""
for _ in $(seq 1 100); do
  screen="$(tmux -L "$SOCK" capture-pane -p 2>/dev/null || true)"
  # lualine's mode segment (globalstatus) shows once the UI is really up.
  printf '%s\n' "$screen" | grep -qE 'NORMAL|\[No Name\]' && break
  sleep 0.2
done
if printf '%s\n' "$screen" | grep -qiE 'Press ENTER|E[0-9]{2,}:|Error detected|attempt to'; then
  echo "---- pane ----"; printf '%s\n' "$screen" >&2
  die "nvim showed an error / Press-ENTER prompt on real-terminal startup"
fi
printf '%s\n' "$screen" | grep -qE 'NORMAL|\[No Name\]' ||
  { echo "---- pane ----"; printf '%s\n' "$screen" >&2; die "nvim did not reach a normal startup screen"; }
echo "== real-terminal startup clean (normal screen, no Press-ENTER) =="

# ---------------------------------------------------------------------------
# Assert 3 (real terminal): holding <leader> pops up which-key, listing the
# maps by the `desc` they were registered with. Everything else about
# which-key can be true (plugin loaded, module required, descs present) while
# the popup itself never renders, so assert on the pixels.
# ---------------------------------------------------------------------------
echo "== which-key popup check =="
# Re-press rather than press once and poll: the pane reaches a normal screen
# before which-key has registered its triggers, and a <leader> that lands in
# that window is just a prefix nobody answers — nvim waits out 'timeoutlen'
# and the popup never comes. Pressing once made this check fail ~2 runs in 8.
# Escape first each round so a half-entered prefix cannot accumulate.
popup=""
for _ in $(seq 1 20); do
  tmux -L "$SOCK" send-keys Escape
  sleep 0.1
  tmux -L "$SOCK" send-keys Space
  sleep 0.5
  popup="$(tmux -L "$SOCK" capture-pane -p 2>/dev/null || true)"
  printf '%s\n' "$popup" | grep -q 'find (telescope)' && break
done
printf '%s\n' "$popup" | grep -q 'find (telescope)' ||
  { echo "---- pane ----"; printf '%s\n' "$popup" >&2
    die "which-key popup did not list the <leader>f group"; }
# A group label alone would still pass with every desc missing; check a real map.
printf '%s\n' "$popup" | grep -q 'Toggle file tree' ||
  { echo "---- pane ----"; printf '%s\n' "$popup" >&2
    die "which-key popup rendered without the <leader>e desc"; }
tmux -L "$SOCK" send-keys Escape
echo "== which-key popup lists groups and descs =="

# ---------------------------------------------------------------------------
# Assert 4 (real terminal): clipboard = unnamedplus really routes a yank out
# of nvim. Without a provider nvim keeps the text to itself, which is the
# state that option exists to fix, and it fails silently. The stub provider
# above stands in for pbcopy — same mechanism, no pasteboard needed.
#
# Driven by real keystrokes rather than a headless `:normal! yy`: in headless
# mode a scripted yank does not mirror into "+ at all (an explicit "+yy does),
# so a headless probe would assert something the editor never does.
# setline over insert mode keeps auto-save's InsertLeave hook out of it.
# ---------------------------------------------------------------------------
echo "== clipboard check =="
tmux -L "$SOCK" send-keys ':call setline(1, "yanked-through-the-provider")' Enter
sleep 0.5
tmux -L "$SOCK" send-keys 'gg' 'yy'
for _ in $(seq 1 40); do
  grep -q 'yanked-through-the-provider' "$HOME_DIR/tmux_clipboard.txt" 2>/dev/null && break
  sleep 0.2
done
grep -q 'yanked-through-the-provider' "$HOME_DIR/tmux_clipboard.txt" 2>/dev/null ||
  { echo "---- pane ----"; tmux -L "$SOCK" capture-pane -p >&2 || true
    die "a plain yy never reached the clipboard provider (clipboard=unnamedplus not in effect)"; }
echo "== yank reaches the system clipboard provider =="

# ---------------------------------------------------------------------------
# Assert 5 (real terminal): nvim-autopairs closes a bracket AND vim-endwise
# still adds `end`. autopairs maps <CR> by default, which silently overrides
# endwise's — measured before map_cr=false went in, `def foo` + Enter in a .rb
# buffer produced no `end` at all. Nothing errors when that regresses, the
# `end` just stops appearing, so it needs a test.
# ---------------------------------------------------------------------------
echo "== autopairs / endwise check =="
rb_file="$HOME_DIR/endwise_probe.rb"
: >"$rb_file"
tmux -L "$SOCK" send-keys ":edit! $rb_file" Enter
sleep 0.5
tmux -L "$SOCK" send-keys 'i'
sleep 0.3
tmux -L "$SOCK" send-keys 'def foo'
sleep 0.5
tmux -L "$SOCK" send-keys Enter
sleep 0.8
tmux -L "$SOCK" send-keys 'bar('
sleep 0.5
tmux -L "$SOCK" send-keys Escape
sleep 0.8
rb_out="$HOME_DIR/endwise_probe.txt"
tmux -L "$SOCK" send-keys \
  ":lua vim.fn.writefile(vim.api.nvim_buf_get_lines(0,0,-1,false), '$rb_out')" Enter
sleep 0.8
echo "---- ruby buffer ----"; cat "$rb_out" 2>/dev/null; echo "---------------------"
grep -q 'bar()' "$rb_out" 2>/dev/null ||
  die "nvim-autopairs did not close the bracket"
grep -qx 'end' "$rb_out" 2>/dev/null ||
  die "vim-endwise did not add 'end' — autopairs has taken over <CR> (map_cr)"
echo "== autopairs closes brackets, endwise still adds end =="

# ---------------------------------------------------------------------------
# Assert 6 (real terminal): <Tab> cycles buffers without eating <C-i>, the
# jumplist's forward motion. Without the kitty keyboard protocol the two are
# the same byte (0x09), so bufferline's <Tab> map silently made <C-o> a
# one-way trip. keymaps.lua maps <C-i> back; this pins both halves:
#   - 0x09 (what a legacy terminal sends for either key) must still cycle
#   - CSI 105;5u (what a kitty-protocol terminal sends for Ctrl+I) must jump
# Bytes are injected raw because tmux's own `send-keys C-i` emits 0x09.
# ---------------------------------------------------------------------------
echo "== <C-i> vs <Tab> check =="
jump_file="$HOME_DIR/jumplist_probe.txt"
seq 1 200 >"$jump_file"
# edit! — the clipboard step above left the scratch buffer modified, and
# 'confirm' would pop a dialog instead of switching.
tmux -L "$SOCK" send-keys ":edit! $jump_file" Enter
sleep 0.5
# G then gg leaves the jumplist as [line 1, line 200] with the cursor on 1,
# so <C-o> goes to 200 and a working <C-i> comes back to 1.
tmux -L "$SOCK" send-keys 'G'
sleep 0.3
tmux -L "$SOCK" send-keys 'gg'
sleep 0.3
tmux -L "$SOCK" send-keys C-o
sleep 0.5
jump_out="$HOME_DIR/jump_probe.txt"
report_pos() {
  tmux -L "$SOCK" send-keys ":call writefile(['$1=' . line('.') . ':' . expand('%:t')], '$jump_out')" Enter
  sleep 0.5
}
report_pos AFTER_CTRL_O
grep -q "AFTER_CTRL_O=200:jumplist_probe.txt" "$jump_out" ||
  { cat "$jump_out"; die "<C-o> did not reach line 200 (test setup broke, not the config)"; }

tmux -L "$SOCK" send-keys -H 1b 5b 31 30 35 3b 35 75   # CSI 105;5u = Ctrl+I
sleep 0.5
report_pos AFTER_CTRL_I
grep -q "AFTER_CTRL_I=1:jumplist_probe.txt" "$jump_out" ||
  { cat "$jump_out"
    die "<C-i> did not jump forward — the <Tab> map is eating it again"; }

tmux -L "$SOCK" send-keys -H 09                        # plain Tab byte
sleep 0.5
report_pos AFTER_TAB
grep -q "AFTER_TAB=.*jumplist_probe.txt" "$jump_out" &&
  { cat "$jump_out"; die "<Tab> stopped cycling buffers"; }
echo "== <C-i> jumps forward, <Tab> still cycles buffers =="

tmux -L "$SOCK" send-keys ':qa!' Enter

# ---------------------------------------------------------------------------
# Assert 7: opening a real .ts file attaches an LSP client. This is what the
# deferred load in init.lua could silently break — vim.lsp.enable() only
# re-runs its FileType autocmd over already-open buffers when it is called
# after VimEnter, and a miss produces no error, just no LSP.
#
# The server is test/fixtures/stub_lsp.py behind a wrapper named
# `typescript-language-server`, first on PATH: nvim resolves lspconfig's real
# ts_ls cmd to it, so the config under test is untouched. Installing a real
# server would test npm instead, and the auto-installers are off here anyway.
# ---------------------------------------------------------------------------
echo "== LSP attach check =="
STUB_BIN="$HOME_DIR/stubbin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexec python3 "%s/test/fixtures/stub_lsp.py"\n' "$REPO" >"$STUB_BIN/typescript-language-server"
chmod +x "$STUB_BIN/typescript-language-server"

TS_PROJECT="$HOME_DIR/tsproject"
mkdir -p "$TS_PROJECT"
echo '{"compilerOptions":{}}' >"$TS_PROJECT/tsconfig.json"
echo 'export const answer: number = 42' >"$TS_PROJECT/probe.ts"

# The probe hangs off VimEnter for the same reason init.lua does: waiting from
# a plain -c command would spin the loop before VimEnter and measure a state
# the real editor never reaches.
lsp_out="$HOME_DIR/lsp_probe.txt"
lsp_probe="$HOME_DIR/lsp_probe.lua"
cat >"$lsp_probe" <<LUAPROBE
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.wait(15000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end)
      local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))
      vim.fn.writefile({
        'FILETYPE=' .. vim.bo.filetype,
        'VIM_DID_ENTER=' .. vim.v.vim_did_enter,
        'LSP_CLIENTS=' .. table.concat(names, ','),
      }, '$lsp_out')
      vim.cmd('qall!')
    end)
  end,
})
LUAPROBE

( cd "$TS_PROJECT" && PATH="$STUB_BIN:$PATH" HOME="$HOME_DIR" \
    nvim --headless probe.ts -c "luafile $lsp_probe" ) </dev/null >"$HOME_DIR/lsp.log" 2>&1 ||
  { cat "$HOME_DIR/lsp.log"; die "nvim exited non-zero on the LSP probe"; }

[ -f "$lsp_out" ] || { cat "$HOME_DIR/lsp.log"; die "LSP probe never wrote its result"; }
echo "---- lsp probe ----"; cat "$lsp_out"; echo "-------------------"
grep -q "FILETYPE=typescript" "$lsp_out" || die "probe.ts did not get filetype=typescript"
grep -q "VIM_DID_ENTER=1"     "$lsp_out" || die "probe ran before VimEnter (test harness bug)"
grep -q "LSP_CLIENTS=ts_ls"   "$lsp_out" ||
  die "no LSP client attached to probe.ts (the deferred vim.lsp.enable missed the open buffer)"
echo "== LSP attached to a .ts file opened on the command line =="

# ---------------------------------------------------------------------------
# Assert 8 (real terminal): the completion menu opens as you type, and ⌃+Y
# takes an item from each source — a word in the buffer, the language server,
# a LuaSnip snippet (expanded, not left as its trigger word), a path — while
# Telescope's prompt gets no menu at all. Only typed keys open 'autocomplete',
# so this goes through tmux; calling the sources directly would skip the menu.
# Every menu that opens is logged with its buffer's filetype.
# ---------------------------------------------------------------------------
echo "== completion check =="
pum_log="$HOME_DIR/pum.log"
lsp_ready="$HOME_DIR/lsp_ready"
: >"$pum_log"
tmux -L "$SOCK" new-session -d -x 180 -y 45 -c "$TS_PROJECT" \
  "env HOME='$HOME_DIR' PATH='$STUB_BIN:$PATH' XDG_CONFIG_HOME='$XDG_CONFIG_HOME' \
       XDG_DATA_HOME='$XDG_DATA_HOME' XDG_STATE_HOME='$XDG_STATE_HOME' XDG_CACHE_HOME='$XDG_CACHE_HOME' \
       TERM=xterm-256color nvim --cmd 'luafile $HOME_DIR/tmux_clipboard.lua' \
       --cmd \"autocmd CompleteChanged * call writefile([&filetype], '$pum_log', 'a')\" \
       --cmd \"autocmd LspAttach * call writefile([], '$lsp_ready')\" probe.ts" ||
  die "failed to start tmux session for the completion check"
for _ in $(seq 1 75); do [ -f "$lsp_ready" ] && break; sleep 0.2; done
[ -f "$lsp_ready" ] || die "the stub language server never attached in the completion pane"
sleep 0.5

# Types $1 on a new line, then takes the first item in the menu.
complete_on_new_line() {
  tmux -L "$SOCK" send-keys Escape
  sleep 0.2
  tmux -L "$SOCK" send-keys o
  sleep 0.3
  tmux -L "$SOCK" send-keys -l "$1"
  sleep 1
  tmux -L "$SOCK" send-keys C-n
  sleep 0.3
  tmux -L "$SOCK" send-keys C-y
  sleep 0.8
  tmux -L "$SOCK" send-keys Escape
  sleep 0.5
}
complete_on_new_line 'ans'
complete_on_new_line 'stubC'
complete_on_new_line './tsc'
complete_on_new_line 'ifac'

completion_out="$HOME_DIR/completion_probe.txt"
tmux -L "$SOCK" send-keys \
  ":lua vim.fn.writefile(vim.api.nvim_buf_get_lines(0,0,-1,false), '$completion_out')" Enter
sleep 0.8
echo "---- typescript buffer ----"; cat "$completion_out" 2>/dev/null; echo "---------------------------"
grep -qx 'answer' "$completion_out" 2>/dev/null ||
  die "a word already in the buffer was not completed"
grep -qx 'stubCompletionItem' "$completion_out" 2>/dev/null ||
  die "the language server's item never reached the completion menu"
grep -q '^interface name {' "$completion_out" 2>/dev/null ||
  die "accepting the iface snippet did not expand it"
grep -qx './tsconfig.json' "$completion_out" 2>/dev/null ||
  die "a path was not completed"

tmux -L "$SOCK" send-keys ':Telescope find_files' Enter
sleep 1
tmux -L "$SOCK" send-keys -l 'pro'
sleep 1.5
tmux -L "$SOCK" send-keys Escape Escape
sleep 0.3
tmux -L "$SOCK" send-keys ':qa!' Enter
echo "---- menus opened (by filetype) ----"; sort "$pum_log" | uniq -c; echo "------------------------------------"
grep -qx 'typescript' "$pum_log" || die "no completion menu was logged in the typescript buffer"
if grep -qx 'TelescopePrompt' "$pum_log"; then
  die "the completion menu opened in Telescope's prompt"
fi
echo "== the menu completes from every source, and stays out of Telescope =="

echo "PASS"
