#!/bin/bash
# Interactive end-to-end test for the keybinding cheatsheet (bin/keys.sh) at
# both keyboards it is bound to:
#
#   zsh   ⌃+X ?          -> keys_widget (.zshrc)
#   tmux  prefix + ?     -> display-popup running ~/bin/keys.sh (.tmux.conf)
#
# The extraction half is unit-tested in test/keys.bats; what only a real
# terminal can prove is the wiring around it. For zsh: that ⌃+X ? actually
# reaches the widget (compinit binds ⌃+X ? to _complete_debug, so this is a
# deliberate override that a load-order change could silently undo), that fzf
# renders inside the pane, and — the property that makes it usable mid-command —
# that the line being edited survives the lookup untouched. For tmux: that the
# popup finds the script through ~/bin at all, which is a path the config can
# only get wrong at runtime.
#
# The tmux half nests tmux the way ci_tmux_keybinding_test.sh does (an OUTER
# vanilla server whose pane runs an INNER server with the real config), because
# send-keys into a plain pane is delivered to the program inside it, never
# interpreted as a tmux binding. HOME is redirected to a sandbox whose bin/ is a
# symlink to this repo's, exactly the shape bin/mklink.sh creates — so the test
# needs no installed dotfiles, and the real linking stays covered by
# test/mklink_rmworld_behaviour.bats.
#
# shellcheck disable=SC2016  # send-keys strings are single-quoted on purpose:
# every `$PWD`/`$(...)` must be evaluated by the zsh inside the pane, not here.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
command -v fzf >/dev/null 2>&1 || die "fzf not installed (keys.sh pipes the rows into fzf)"
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
[ -x "$REPO/bin/keys.sh" ] || die "no executable bin/keys.sh in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version), $(fzf --version) =="

TMP="$(mktemp -d)"
SOCK="ci_keys_e2e_$$"
OUTER="ci_keys_out_$$"
INNER="ci_keys_in_$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  tmux -L "$INNER" kill-server 2>/dev/null || true
  tmux -L "$OUTER" kill-server 2>/dev/null || true
  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# zsh: ⌃+X ? opens the picker mid-command and gives the command line back.
# ---------------------------------------------------------------------------
tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# 0) Shell is live.
tmux -L "$SOCK" send-keys 'echo __KEYS_READY__$((6 * 7))' Enter
wait_for_pane "$SOCK" "__KEYS_READY__42"
echo "== shell live =="

# 1) Type a command but do NOT run it, then ask for the cheatsheet. fzf must
#    come up with the rows keys.sh built — asserted on the first layer of the
#    document (the list is far taller than the pane, so only its head is on
#    screen) rather than on fzf's own chrome.
tmux -L "$SOCK" send-keys 'echo __KEYS_KEPT__'
tmux -L "$SOCK" send-keys C-x
tmux -L "$SOCK" send-keys '?'
wait_for_pane "$SOCK" 'keys>'
wait_for_pane "$SOCK" '\[macOS'
echo "== ⌃+X ? opened the cheatsheet over KEYBINDINGS.md =="

# 2) Typing narrows across every layer, and the layer tag rides along — which
#    is the whole point of tagging the rows: `f` alone means three things.
tmux -L "$SOCK" send-keys 'extrakto'
wait_for_pane "$SOCK" '\[tmux .*extrakto'
echo "== typing a query narrows the list, layer tag included =="

# 3) Esc closes it, and the half-typed command line is still there — nothing
#    inserted, nothing lost. Enter then runs exactly what was typed in step 1.
tmux -L "$SOCK" send-keys Escape
wait_absent_pane "$SOCK" 'keys>'
tmux -L "$SOCK" send-keys Enter
wait_for_pane "$SOCK" '^__KEYS_KEPT__$'
echo "== Esc restored the command line under edit, unchanged =="

# ---------------------------------------------------------------------------
# tmux: prefix + ? opens the same picker in a popup, via ~/bin/keys.sh.
# ---------------------------------------------------------------------------
CONF="$(tmux_conf_path)"
echo "== driving bindings from: $CONF =="

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"
ln -s "$REPO/bin" "$FAKE_HOME/bin"

# OUTER is vanilla (-f /dev/null): its bindings must not shadow the keys we
# send. Its single pane runs the INNER tmux, which loads the config under test.
tmux -L "$OUTER" -f /dev/null new-session -d -x 200 -y 50 \
  "env HOME='$FAKE_HOME' tmux -L '$INNER' -f '$CONF' new-session" ||
  die "failed to start nested tmux"

i=0
while [ "$i" -lt 100 ]; do
  tmux -L "$INNER" list-windows >/dev/null 2>&1 && break
  i=$((i + 1)); sleep 0.1
done
[ "$i" -lt 100 ] || die "the nested tmux server never came up"
echo "== nested tmux is live =="

# 4) prefix + ? pops up the picker, pre-filtered to the tmux layer. Assert on a
#    tmux row and on the absence of another layer's, which together prove both
#    that the popup found ~/bin/keys.sh and that the `tmux` query was passed.
tmux -L "$OUTER" send-keys C-t
tmux -L "$OUTER" send-keys '?'
wait_for_pane "$OUTER" 'keys>'
wait_for_pane "$OUTER" '\[tmux '
if tmux -L "$OUTER" capture-pane -p | grep -qE '\[Neovim'; then
  die "prefix + ? did not pre-filter to the tmux layer"
fi
tmux -L "$OUTER" send-keys 'lazygit'
wait_for_pane "$OUTER" '\[tmux .*lazygit'
echo "== prefix + ? opened the cheatsheet popup, filtered to tmux =="

# 5) Esc closes the popup and hands the pane back.
tmux -L "$OUTER" send-keys Escape
wait_absent_pane "$OUTER" 'keys>'
echo "== Esc closed the popup =="

echo "PASS"
