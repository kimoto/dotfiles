#!/bin/bash
# Interactive end-to-end test for tmux copy-mode (vi): the select-and-yank flow.
# When a pane is in copy-mode, send-keys is interpreted by tmux's copy-mode-vi
# key table (not the program in the pane), so a sent `v`/`y` exercise the real
# bindings from .tmux.conf:
#   bind-key -T copy-mode-vi v send-keys -X begin-selection
#   bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
# `y` pipes to pbcopy (macOS only), but copy-pipe ALSO stores the selection in a
# tmux paste buffer regardless of the pipe command, so asserting on `show-buffer`
# works headless on Linux too (pbcopy simply isn't there and is ignored).
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew tmux (newer) when the shellenv is available.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v tmux >/dev/null 2>&1 || die "tmux not installed"
echo "== $(tmux -V) =="

CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
[ -f "$CONF" ] || CONF="$PWD/.tmux.conf"
[ -f "$CONF" ] || die "no .tmux.conf found"
echo "== copy-mode bindings from: $CONF =="

SOCK="ci_tmux_copy_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Poll capture-pane until $1 (a grep -E pattern) appears, or time out.
wait_for() {
  local pattern="$1" tries="${2:-50}" i=0
  while [ "$i" -lt "$tries" ]; do
    tmux -L "$SOCK" capture-pane -p 2>/dev/null | grep -qE "$pattern" && return 0
    i=$((i + 1)); sleep 0.1
  done
  echo "---- pane at timeout ----" >&2
  tmux -L "$SOCK" capture-pane -p >&2 2>/dev/null || true
  die "timed out waiting for: $pattern"
}

tmux -L "$SOCK" -f "$CONF" new-session -d -x 120 -y 30 || die "failed to start tmux"

# Put a known line on screen, then wait until it has actually rendered so the
# copy-mode search below can find it.
tmux -L "$SOCK" send-keys 'printf "ALPHA BRAVO CHARLIE\\n"' Enter
wait_for 'ALPHA BRAVO CHARLIE'
echo "== marker line rendered =="

# Enter copy-mode, jump to the middle word, then drive the real bindings:
# `v` must begin a selection (default vi `v` is rectangle-toggle, so this only
# works because .tmux.conf rebinds it), `e` extends to the word end, `y` yanks.
tmux -L "$SOCK" copy-mode
tmux -L "$SOCK" send-keys -X search-backward "BRAVO"
tmux -L "$SOCK" send-keys v
tmux -L "$SOCK" send-keys e
tmux -L "$SOCK" send-keys y

# The yank lands in tmux's paste buffer. Poll for it (copy-pipe is async-ish).
got=""
for _ in $(seq 1 50); do
  got="$(tmux -L "$SOCK" show-buffer 2>/dev/null || true)"
  [ "$got" = "BRAVO" ] && break
  sleep 0.1
done
[ "$got" = "BRAVO" ] || die "expected yanked buffer 'BRAVO', got '${got:-<empty>}'"
echo "== copy-mode v/y selected and yanked 'BRAVO' =="

echo "PASS"
