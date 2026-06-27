#!/bin/bash
# Fast guard test for the legacy .vimrc: on a machine with NO plugins installed,
# Vim must still start completely clean instead of erroring on every NeoBundle
# command and blocking on a "Press ENTER" prompt.
#
# This exercises the degrade-gracefully path of .vimrc's bootstrap: with
# $VIM_NO_BOOTSTRAP set, the auto-install of neobundle is skipped, so the whole
# plugin block is guarded out. It installs nothing and touches no network, so
# unlike ci_vim_loading_test.sh (the full monthly install) this is cheap enough
# to run on every push.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

command -v vim  >/dev/null 2>&1 || die "vim not installed"
command -v tmux >/dev/null 2>&1 || die "tmux not installed"
REPO="$PWD"
VIMRC="$REPO/.vimrc"
[ -f "$VIMRC" ] || die "no .vimrc in $REPO"
echo "== $(vim --version | head -1) =="

HOME_DIR="$(mktemp -d)"
SOCK="ci_vim_guard_$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$HOME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Isolated HOME with an empty bundle dir: no neobundle, no plugins.
mkdir -p "$HOME_DIR/.vim/bundle" "$HOME_DIR/.vim/undo" "$HOME_DIR/tmp"
cp "$VIMRC" "$HOME_DIR/.vimrc"

# Assert 1 (headless): sourcing .vimrc with no plugins yields no error messages,
# exits cleanly, and really is in the guarded path (the NeoBundle command, which
# only the plugin manager defines, must be absent).
echo "== headless: no-plugin startup must be clean =="
msgs="$HOME_DIR/messages.txt"
HOME="$HOME_DIR" VIM_NO_BOOTSTRAP=1 vim -N -u "$HOME_DIR/.vimrc" \
  -c 'set nomore' \
  -c "redir! > $msgs" \
  -c 'silent messages' \
  -c 'silent echo "NEOBUNDLE_CMD=".(exists(":NeoBundle")?"present":"absent")' \
  -c 'redir END' -c 'qall!' </dev/null >/dev/null 2>&1 || die "vim exited non-zero with no plugins"

echo "---- :messages ----"; cat "$msgs"; echo "-------------------"
if grep -nE "E[0-9]{2,}:|Not an editor command|Unknown function|Cannot find color scheme|Error detected" "$msgs"; then
  die "no-plugin startup produced Vim errors (the guard regressed)"
fi
grep -q "NEOBUNDLE_CMD=absent" "$msgs" ||
  die "expected the guarded path (NeoBundle command should be undefined without plugins)"
echo "== headless no-plugin startup clean =="

# Assert 2 (real terminal): confirm there is no "Press ENTER" prompt or error
# wall — the original symptom — and Vim lands on a normal editing screen.
echo "== real-terminal: no Press-ENTER / error wall =="
tmux -L "$SOCK" new-session -d -x 120 -y 40 \
  "env HOME='$HOME_DIR' VIM_NO_BOOTSTRAP=1 TERM=xterm-256color vim -N -u '$HOME_DIR/.vimrc'" ||
  die "failed to start tmux session"

screen=""
for _ in $(seq 1 50); do
  screen="$(tmux -L "$SOCK" capture-pane -p 2>/dev/null || true)"
  printf '%s\n' "$screen" | grep -qE '\[No Name\]|VIM - Vi IMproved' && break
  sleep 0.1
done
if printf '%s\n' "$screen" | grep -qiE 'Press ENTER|Not an editor command|E[0-9]{2,}:|Unknown function'; then
  echo "---- pane ----"; printf '%s\n' "$screen" >&2
  die "Vim showed an error / Press-ENTER prompt on no-plugin startup (guard regressed)"
fi
printf '%s\n' "$screen" | grep -qE '\[No Name\]|VIM - Vi IMproved' ||
  { echo "---- pane ----"; printf '%s\n' "$screen" >&2; die "Vim did not reach a normal startup screen"; }
tmux -L "$SOCK" send-keys ':qa!' Enter
echo "== real-terminal no-plugin startup clean =="

echo "PASS"
