#!/bin/bash
# Interactive end-to-end test for tmux copy-mode (vi): the select-and-yank flow.
# When a pane is in copy-mode, send-keys is interpreted by tmux's copy-mode-vi
# key table (not the program in the pane), so a sent `v`/`y` exercise the real
# bindings from .tmux.conf:
#   bind-key -T copy-mode-vi v send-keys -X begin-selection
#   bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy ... || wl-copy ... || xclip ..."
# `y` pipes to the first clipboard tool present, but copy-pipe ALSO stores the
# selection in a tmux paste buffer regardless of the pipe command, so asserting
# on `show-buffer` works headless too (no clipboard tool needed).
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
echo "== copy-mode bindings from: $CONF =="

SOCK="ci_tmux_copy_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" -f "$CONF" new-session -d -x 120 -y 30 || die "failed to start tmux"

# Put a known line on screen, then wait until it has actually rendered so the
# copy-mode search below can find it.
tmux -L "$SOCK" send-keys 'printf "ALPHA BRAVO CHARLIE\\n"' Enter
wait_for_pane "$SOCK" 'ALPHA BRAVO CHARLIE'
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
