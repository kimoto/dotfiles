#!/bin/bash
# Interactive end-to-end test: drives a real terminal by sending keystrokes into
# a tmux pane and asserting on the rendered screen (capture-pane) — the TUI
# equivalent of a browser e2e (Playwright). This is deliberately distinct from
# ci_zsh_loading_test.sh: that one only checks that .zshrc *loads* (via a
# `script` pty), whereas this drives an interactive zsh rendered in a real
# terminal and verifies it responds correctly to typed input and zle key
# presses — the line editor, history recall, and aliases-in-a-real-tty path that
# a non-interactive load can never exercise.
#
# Scope note: tmux's own key bindings (prefix tables) cannot be exercised this
# way. `send-keys` feeds the pane's program directly and bypasses tmux's key
# interpretation, so a sent `M-t` reaches zsh rather than triggering a binding.
# Driving tmux bindings would require attaching a real client, which is not
# available headless; .tmux.conf parsing is covered by ci_tmux_loading_test.sh.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
# step 5 asserts on what `ll` renders, and `ll` is eza (Brewfile.basic).
need eza
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

SOCK="ci_tmux_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Prime the wordcode cache before the pane starts. .zshrc compiles itself to
# <ZDOTDIR>/.zshrc.zwc at the end of its own load, so the very first shell on a
# machine parses the source and every shell after it maps the .zwc instead —
# and zcompile resolves aliases at *compile* time, so the two paths can disagree
# about what a function body ended up containing. A single pane would only ever
# exercise the first-shell path and never see that skew; burning one throwaway
# shell here puts the pane below in the state every real shell is in.
# zsh_pane_cmd already spells out the env the pane runs under, so the warm-up
# borrows it wholesale rather than hand-building a second copy that could drift.
eval "$(zsh_pane_cmd) -c true" >/dev/null 2>&1 || true
if [ -f "$REPO/.zshrc.zwc" ]; then
  echo "== wordcode cache primed: the pane loads .zshrc.zwc =="
else
  echo "== no .zshrc.zwc after warm-up: the pane loads the source =="
fi

# Launch an *interactive* zsh inside a real (tmux) terminal, under the shared
# CI pane conventions (see zsh_pane_cmd in tmux_e2e_helpers.sh).
tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# Isolate the window-rename assertion (step 4) from tmux itself: with the
# repo's .tmux.conf loaded, automatic-rename would follow pane_current_path
# and could rename the window even if the zsh hook under test never ran.
WIN_ID="$(tmux -L "$SOCK" display-message -p '#{window_id}')"
tmux -L "$SOCK" set-option -w -t "$WIN_ID" automatic-rename off

# 1) The interactive shell is live and rendering. Typing a command and seeing
#    its *computed* output ($((6 * 7)) -> 42) on screen proves the full
#    keystroke -> eval -> render path through a genuine terminal.
# shellcheck disable=SC2016  # single-quoted on purpose: zsh in the pane must
# evaluate $((6 * 7)), not this shell.
# This first wait absorbs the whole interactive startup (compinit, evalcache
# population on a cold runner), which can blow past the default 5s budget —
# give it 30s. Later waits keep the default: once the prompt is up, each step
# is a single keystroke round-trip.
tmux -L "$SOCK" send-keys 'echo __E2E_READY__$((6 * 7))' Enter
wait_for_pane "$SOCK" '__E2E_READY__42' 300
echo "== shell is live (echo rendered in pane) =="

# 2) .zshrc actually took effect in a real tty (not just under `script`): an
#    alias it defines resolves interactively. The command line is `type vi`, so
#    only the result line "vi is an alias for nvim" matches vi.*nvim.
#    Same 30s budget as step 1: __E2E_READY__42 can render while zsh-defer is
#    still draining the deferred plugin init (fast-syntax-highlighting,
#    autosuggestions, carapace), so on a slow runner the shell may not process
#    this second command within the default 5s — the wait returns the instant
#    the line appears, so the larger ceiling only removes the flake.
tmux -L "$SOCK" send-keys 'type vi' Enter
wait_for_pane "$SOCK" 'vi.*nvim' 300
echo "== alias resolves interactively (vi -> nvim) =="

# 3) The zsh line editor (zle) responds to a real key press. After running a
#    marked command, C-l (clear-screen, a zle widget that adds no history entry)
#    wipes the pane; pressing Up must then redraw that command into the edit
#    buffer. Clearing first makes the assertion unambiguous: the marker can only
#    reappear via history recall, not from leftover scrollback.
tmux -L "$SOCK" send-keys 'echo __E2E_HIST_MARK__' Enter
wait_for_pane "$SOCK" '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-l
wait_absent_pane "$SOCK" '__E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys Up
wait_for_pane "$SOCK" 'echo __E2E_HIST_MARK__'
tmux -L "$SOCK" send-keys C-c
echo "== zle Up-arrow recalled previous command =="

# 4) update_tmux_window: after a cd, the chpwd hook must rename the tmux window
#    to the directory tail. `builtin cd` bypasses the interactive cd->z alias so
#    the assertion does not depend on zoxide being installed. mktemp's basename
#    contains a '.' on purpose: tmux >= 3.7 rejects '.'/':' in window names
#    (target separators), so the hook must sanitize them — pin that here.
e2e_dir="$(mktemp -d)"
e2e_base="$(basename "$e2e_dir")"
e2e_name="$(printf '%s' "$e2e_base" | tr '.:' '__')"
tmux -L "$SOCK" send-keys "builtin cd '$e2e_dir'" Enter
i=0
while [ "$i" -lt 50 ]; do
  [ "$(tmux -L "$SOCK" display-message -p '#W' 2>/dev/null)" = "$e2e_name" ] && break
  i=$((i + 1)); sleep 0.1
done
window_name="$(tmux -L "$SOCK" display-message -p '#W')"
rmdir "$e2e_dir" 2>/dev/null || true
if [ "$window_name" != "$e2e_name" ]; then
  # Dump enough state to diagnose from the CI log alone: what's on screen
  # (command-not-found noise, plugin errors), the window list, whether a
  # manual rename disabled automatic-rename, and the hook state in the pane.
  {
    echo "---- diagnostics: windows ----"
    tmux -L "$SOCK" list-windows -a \
      -F '#{window_id} name=#{window_name} active=#{window_active} panes=#{window_panes} path=#{pane_current_path}'
    echo "---- diagnostics: automatic-rename ----"
    tmux -L "$SOCK" show-options -w automatic-rename || true
    echo "---- diagnostics: pane hook state ----"
    # shellcheck disable=SC2016  # single-quoted on purpose: the pane's zsh
    # must expand these, not this shell.
    tmux -L "$SOCK" send-keys \
      'print "TMUX=$TMUX cache=${_tmux_window_name:-}"; whence -w update_tmux_window; print -l $chpwd_functions' Enter
    sleep 1
    echo "---- diagnostics: pane contents ----"
    tmux -L "$SOCK" capture-pane -p
  } >&2 || true
  die "tmux window was not renamed to $e2e_name (got: $window_name)"
fi
echo "== tmux window renamed to the cd target ($e2e_name) =="

# 5) chpwd: every cd must list the directory it landed in (the `ll` call in
#    .zshrc's chpwd hook). The assertion is a marker *file name* that the typed
#    command line never mentions, so the only way it can reach the screen is the
#    hook genuinely listing the directory. C-l first, so a listing left over
#    from step 4's cd cannot be mistaken for this one. `builtin cd` again, for
#    the same reason as step 4.
ll_dir="$(mktemp -d)"
: >"$ll_dir/__E2E_LL_MARKER__"
tmux -L "$SOCK" send-keys C-l
tmux -L "$SOCK" send-keys "builtin cd '$ll_dir'" Enter
wait_for_pane "$SOCK" '__E2E_LL_MARKER__'
# The hook must list *silently*: a `command not found` here means chpwd ran but
# could not resolve what it calls (e.g. an alias that the .zwc left unexpanded),
# which no amount of rendered output would tell us apart from success.
if tmux -L "$SOCK" capture-pane -p | grep -q 'command not found'; then
  tmux -L "$SOCK" capture-pane -p >&2
  rm -rf "$ll_dir"
  die "chpwd could not resolve the command it lists with"
fi
rm -rf "$ll_dir"
echo "== chpwd listed the directory after cd (auto ll) =="

echo "PASS"
