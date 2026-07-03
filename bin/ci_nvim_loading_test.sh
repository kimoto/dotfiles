#!/bin/bash
# End-to-end test for the Neovim config (config/nvim): bootstrap vim-jetpack
# exactly as setup_plugin.lua does on a fresh machine, install every declared
# plugin with :JetpackSync, then assert a full init.lua startup is clean.
#
# This is the nvim analogue of ci_vim_loading_test.sh and the layer above
# ci_nvim_guard_test.sh (which loads only the plugin-free basic_config.lua).
# It needs the network (jetpack bootstrap curl + one clone per plugin), so it
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
# produces (~/.config -> config/). Only XDG_DATA_HOME (jetpack + plugin
# clones) is optionally persistent so CI can cache it across runs.
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="${NVIM_E2E_DATA_DIR:-$HOME_DIR/.local/share}"
export XDG_STATE_HOME="$HOME_DIR/.local/state"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
ln -s "$REPO/config/nvim" "$XDG_CONFIG_HOME/nvim"

run_nvim() { HOME="$HOME_DIR" nvim --headless "$@" </dev/null; }

# ---------------------------------------------------------------------------
# Install: the first startup bootstraps jetpack (setup_plugin.lua curls it),
# then :JetpackSync clones every declared plugin and runs the post-install
# hooks (:TSUpdate). Errors from init.lua itself are expected on this run —
# the per-plugin requires fire before anything is installed — so this phase
# only has to leave a complete plugin tree behind; correctness of the config
# is asserted by the startup checks below.
# ---------------------------------------------------------------------------
echo "== JetpackSync (bootstrap + install all plugins) =="
sync_log="$HOME_DIR/sync.log"
run_nvim -c 'JetpackSync' -c 'qall!' >"$sync_log" 2>&1 || {
  cat "$sync_log"; die "JetpackSync run exited non-zero"; }
tail -n 20 "$sync_log"

# JetpackSync reports per-plugin failures only in its progress buffer, so
# verify the end state directly: representative plugins must exist somewhere
# under the jetpack pack dir (layout-agnostic: src clone or copied pack tree).
PACK_DIR="$XDG_DATA_HOME/nvim/site/pack/jetpack"
[ -d "$PACK_DIR" ] || die "jetpack pack dir missing after sync ($PACK_DIR)"
for p in telescope.nvim nvim-tree.lua mason.nvim nvim-cmp onedark.nvim nvim-treesitter; do
  find "$PACK_DIR" -maxdepth 6 -type d -name "$p" 2>/dev/null | grep -q . ||
    die "plugin $p not installed under $PACK_DIR (JetpackSync incomplete / clone failed?)"
done
echo "== plugin tree present =="

# ---------------------------------------------------------------------------
# Assert 1 (headless): a full init.lua startup produces no error messages and
# representative plugins really loaded — commands defined, colorscheme
# applied, lualine required, yanky mappings active. A short sleep lets
# just-after-startup async work surface errors before :messages is dumped.
# ---------------------------------------------------------------------------
echo "== headless startup check =="
msgs="$HOME_DIR/messages.txt"
startup_log="$HOME_DIR/startup.log"
# The probes go through a sourced file, not one -c per probe: nvim rejects
# more than 10 "-c command" arguments outright.
probe="$HOME_DIR/probe.vim"
cat >"$probe" <<PROBE
set nomore
sleep 500m
redir! > $msgs
silent messages
silent echo "TELESCOPE=".(exists(":Telescope")?"loaded":"missing")
silent echo "NVIMTREE=".(exists(":NvimTreeToggle")?"loaded":"missing")
silent echo "TOGGLETERM=".(exists(":ToggleTerm")?"loaded":"missing")
silent echo "TREESITTER=".(exists(":TSUpdate")?"loaded":"missing")
silent echo "MASON=".(exists(":Mason")?"loaded":"missing")
silent echo "CMP=".(luaeval("package.loaded['cmp'] ~= nil")?"loaded":"missing")
silent echo "CONFORM=".(luaeval("package.loaded['conform'] ~= nil")?"loaded":"missing")
silent echo "LSP_TS=".(luaeval("vim.lsp.config['ts_ls'] ~= nil")?"configured":"missing")
silent echo "COLORSCHEME=".(exists("g:colors_name")?g:colors_name:"none")
silent echo "LUALINE=".(luaeval("package.loaded['lualine'] ~= nil")?"loaded":"missing")
silent echo "YANKY_P=".(maparg("p","n")=~#"Yanky"?"mapped":"missing")
redir END
qall!
PROBE
run_nvim -c "source $probe" >"$startup_log" 2>&1 || {
  echo "---- startup output ----"; cat "$startup_log"
  die "nvim exited non-zero on startup"; }

echo "---- :messages ----"; cat "$msgs"; echo "-------------------"
if grep -nE "E[0-9]{2,}:|Error detected|Unknown function|module '.*' not found|attempt to" "$msgs"; then
  die "startup produced errors (see :messages above)"
fi
grep -q "TELESCOPE=loaded"    "$msgs" || die "telescope did not load"
grep -q "NVIMTREE=loaded"     "$msgs" || die "nvim-tree did not load"
grep -q "TOGGLETERM=loaded"   "$msgs" || die "toggleterm did not load"
grep -q "TREESITTER=loaded"   "$msgs" || die "nvim-treesitter did not load"
grep -q "MASON=loaded"        "$msgs" || die "mason did not load"
grep -q "CMP=loaded"          "$msgs" || die "nvim-cmp did not load"
grep -q "CONFORM=loaded"      "$msgs" || die "conform did not load"
grep -q "LSP_TS=configured"   "$msgs" || die "ts_ls lsp config not resolved"
grep -q "COLORSCHEME=onedark" "$msgs" || die "onedark colorscheme not applied"
grep -q "LUALINE=loaded"      "$msgs" || die "lualine did not load"
grep -q "YANKY_P=mapped"      "$msgs" || die "yanky put mapping not active"
echo "== headless startup clean (no errors, plugins + colorscheme loaded) =="

# ---------------------------------------------------------------------------
# Assert 2 (real terminal): drive nvim in a real tmux pane and confirm it
# lands on a normal editing screen — lualine rendered, no error wall and no
# blocking "Press ENTER" prompt (the classic broken-config symptom that a
# headless run can miss for UI-time errors).
# ---------------------------------------------------------------------------
echo "== real-terminal startup check =="
tmux -L "$SOCK" new-session -d -x 180 -y 45 \
  "env HOME='$HOME_DIR' XDG_CONFIG_HOME='$XDG_CONFIG_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' \
       XDG_STATE_HOME='$XDG_STATE_HOME' XDG_CACHE_HOME='$XDG_CACHE_HOME' \
       TERM=xterm-256color nvim" ||
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
tmux -L "$SOCK" send-keys ':qa!' Enter
echo "== real-terminal startup clean (normal screen, no Press-ENTER) =="

echo "PASS"
