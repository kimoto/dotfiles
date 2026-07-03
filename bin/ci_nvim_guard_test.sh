#!/bin/bash
# Fast guard test for the Neovim config: on a machine with NO plugins installed
# and no network, the hand-edited Lua config (config/nvim/lua/kimoto/
# basic_config.lua) must load cleanly in a real headless nvim and actually apply
# the options it sets.
#
# Scope note: init.lua's second line, require('kimoto/setup_plugin'), curls
# vim-jetpack from GitHub and pulls dozens of plugins on first start, and the
# per-plugin requires that follow it (lualine, gitsigns, telescope, ...) all need
# those plugins present. None of that is hermetic, so the full init.lua startup
# is covered by ci_nvim_loading_test.sh (its own CI job, with the plugin tree
# cached), not here. What this guards cheaply is the
# pure-config layer we actually hand-edit: basic_config.lua is plain
# vim.opt/keymap Lua with no plugin dependency. This loads exactly that module
# (via a minimal init that only adds config/nvim to the runtimepath) and asserts
# both that it produces no Lua/Vim errors AND that its options really took effect
# — a typo'd option name would otherwise fail silently. This is the nvim analogue
# of ci_vim_guard_test.sh.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew nvim (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v nvim >/dev/null 2>&1 || die "nvim not installed"
REPO="$PWD"
CONFIG="$REPO/config/nvim/lua/kimoto/basic_config.lua"
[ -f "$CONFIG" ] || die "no basic_config.lua at $CONFIG"
echo "== $(nvim --version | head -1) =="

# Isolated HOME + XDG dirs: even though we never require setup_plugin (the
# network bootstrap), point nvim's config/data/state/cache at a throwaway tree so
# a stray write can't touch the real environment and the run is reproducible.
HOME_DIR="$(mktemp -d)"
cleanup() { rm -rf "$HOME_DIR" 2>/dev/null || true; }
trap cleanup EXIT
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_STATE_HOME="$HOME_DIR/.local/state"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

# Minimal init that loads ONLY the pure-config module — not init.lua, so the
# jetpack curl and the per-plugin requires never run.
INIT="$HOME_DIR/init.lua"
cat > "$INIT" <<EOF
vim.opt.runtimepath:append('$REPO/config/nvim')
require('kimoto/basic_config')
EOF

# Headless: source the config, then dump :messages and the resulting option
# values into a file we can assert on.
msgs="$HOME_DIR/messages.txt"
HOME="$HOME_DIR" nvim --headless -u "$INIT" \
  -c 'set nomore' \
  -c "redir! > $msgs" \
  -c 'silent messages' \
  -c 'silent echo "TABSTOP=" . &tabstop' \
  -c 'silent echo "SHIFTWIDTH=" . &shiftwidth' \
  -c 'silent echo "EXPANDTAB=" . (&expandtab ? "on" : "off")' \
  -c 'silent echo "RELATIVENUMBER=" . (&relativenumber ? "on" : "off")' \
  -c 'silent echo "IGNORECASE=" . (&ignorecase ? "on" : "off")' \
  -c 'redir END' -c 'qall!' </dev/null >/dev/null 2>&1 ||
  die "nvim exited non-zero loading basic_config.lua"

echo "---- :messages ----"; cat "$msgs"; echo "-------------------"

# 1) No Lua/Vim errors surfaced while sourcing the config.
if grep -nE "E[0-9]{2,}:|Error detected|Unknown function|module '.*' not found|attempt to" "$msgs"; then
  die "basic_config.lua produced errors on load (the guard regressed)"
fi

# 2) The options it sets actually took effect — proves the file really loaded and
#    that no option name silently no-op'd.
grep -q "TABSTOP=2"         "$msgs" || die "expected tabstop=2 (basic_config did not apply)"
grep -q "SHIFTWIDTH=2"      "$msgs" || die "expected shiftwidth=2"
grep -q "EXPANDTAB=on"      "$msgs" || die "expected expandtab on"
grep -q "RELATIVENUMBER=on" "$msgs" || die "expected relativenumber on"
grep -q "IGNORECASE=on"     "$msgs" || die "expected ignorecase on"

echo "PASS"
