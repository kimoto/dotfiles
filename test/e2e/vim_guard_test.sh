#!/bin/bash
# Guard test for .vimrc, the fallback editor on machines without nvim: Vim must
# start completely clean with nothing but the OS's vim, and stay plugin-free.
# It installs nothing and touches no network, so it runs on every push.
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

# Isolated HOME laid out as mkworld leaves it: ~/tmp for backups, ~/.vim/undo.
mkdir -p "$HOME_DIR/.vim/undo" "$HOME_DIR/tmp"
cp "$VIMRC" "$HOME_DIR/.vimrc"
msgs="$HOME_DIR/messages.txt"

# Assert 1 (headless): startup yields no error messages, exits cleanly, and
# sources no script from $HOME besides .vimrc itself: a plugin, or a plugin
# manager, would show up there.
echo "== headless: startup must be clean and plugin-free =="
scripts="$HOME_DIR/scriptnames.txt"
HOME="$HOME_DIR" vim -N -u "$HOME_DIR/.vimrc" \
  -c 'set nomore' \
  -c "redir! > $msgs" -c 'silent messages' -c 'redir END' \
  -c "redir! > $scripts" -c 'silent scriptnames' -c 'redir END' \
  -c 'qall!' </dev/null >/dev/null 2>&1 || die "vim exited non-zero on startup"
echo "---- :messages ----"; cat "$msgs"; echo "-------------------"
if grep -nE "E[0-9]{2,}:|Not an editor command|Unknown function|Cannot find color scheme|Error detected" "$msgs"; then
  die "startup produced Vim errors"
fi
# :scriptnames shortens paths under $HOME to ~/, so match that form.
grep -qE ' ~/\.vimrc$' "$scripts" || die ":scriptnames does not list ~/.vimrc; the check below would prove nothing"
if grep -E ' ~/' "$scripts" | grep -vE ' ~/\.vimrc$'; then
  die "vim sourced a script from \$HOME besides .vimrc: .vimrc must load no plugins"
fi
echo "== headless startup clean and plugin-free =="

# Assert 2 (real terminal): no "Press ENTER" prompt or error wall, and Vim
# lands on a normal editing screen.
echo "== real-terminal: no Press-ENTER / error wall =="
tmux -L "$SOCK" new-session -d -x 120 -y 40 \
  "env HOME='$HOME_DIR' TERM=xterm-256color vim -N -u '$HOME_DIR/.vimrc'" ||
  die "failed to start tmux session"

screen=""
for _ in $(seq 1 50); do
  screen="$(tmux -L "$SOCK" capture-pane -p 2>/dev/null || true)"
  printf '%s\n' "$screen" | grep -qE '\[No Name\]|VIM - Vi IMproved' && break
  sleep 0.1
done
if printf '%s\n' "$screen" | grep -qiE 'Press ENTER|Not an editor command|E[0-9]{2,}:|Unknown function'; then
  echo "---- pane ----"; printf '%s\n' "$screen" >&2
  die "Vim showed an error / Press-ENTER prompt on startup"
fi
printf '%s\n' "$screen" | grep -qE '\[No Name\]|VIM - Vi IMproved' ||
  { echo "---- pane ----"; printf '%s\n' "$screen" >&2; die "Vim did not reach a normal startup screen"; }
tmux -L "$SOCK" send-keys ':qa!' Enter
echo "== real-terminal startup clean =="

echo "PASS"
