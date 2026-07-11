#!/bin/bash
# Interactive end-to-end test for the Starship prompt: drives a real terminal via
# tmux send-keys + capture-pane (the TUI analogue of a browser e2e) and asserts
# on what Starship actually renders.
#
# .zshrc only sets a *fallback* zsh PROMPT; the real prompt is Starship, brought
# up by sheldon as `_evalcache starship init zsh` (config/sheldon/plugins.toml).
# Three things can only be proven by rendering it for real:
#   1. Starship — not the fallback PROMPT — is what reaches the screen. The
#      fallback has no date; config/starship.toml enables the [time] module
#      (format '%Y-%m-%d %T'), so a rendered timestamp is an unambiguous
#      "Starship is live" signal.
#   2. the [directory] module reflects $PWD: started in a uniquely-named dir, the
#      prompt shows that dir name.
#   3. the `px` helper in .zshrc round-trips STARSHIP_CONFIG between the main and
#      sub configs (starship.toml <-> starship_sub.toml), the documented way to
#      switch prompt layouts.
#
# Like ci_tmux_interactive_test.sh, this needs a Starship install and the
# repo's ~/.config (symlinked by mkworld); it runs in the same CI job, after the
# loading tests.
set -euo pipefail

# Shared e2e plumbing: die/need, the brew shellenv, and zsh_pane_cmd.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
command -v starship >/dev/null 2>&1 || die "starship not installed (prompt is rendered by it)"
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
[ -f "$REPO/config/starship.toml" ] || die "no config/starship.toml in $REPO"
[ -f "$REPO/config/starship_sub.toml" ] || die "no config/starship_sub.toml in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version), $(starship --version | head -1) =="

SOCK="ci_starship_e2e_$$"
# A uniquely-named start directory so the [directory] segment is unambiguous: the
# marker is the final path component, which Starship always shows (it truncates
# leading components, never the tail).
WORK="$(mktemp -d)/starship_e2e_zone"
mkdir -p "$WORK"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$(dirname "$WORK")" 2>/dev/null || true
}
trap cleanup EXIT

# Poll capture-pane until $1 (a grep -E pattern) appears, or time out. Sampling
# in a loop keeps the test as fast as the shell on a quick runner and as
# forgiving as needed on a slow one. Default 150 tries * 0.1s = 15s: the first
# assertion waits for starship's prompt, which only renders once the deferred
# starship init has run, and zsh-defer can keep draining past the first prompt
# on a loaded runner (see the 15s default in tmux_e2e_helpers.sh's wait_for_pane).
wait_for() {
  local pattern="$1" tries="${2:-150}" i=0
  while [ "$i" -lt "$tries" ]; do
    if tmux -L "$SOCK" capture-pane -p 2>/dev/null | grep -qE "$pattern"; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  echo "---- pane contents at timeout ----" >&2
  tmux -L "$SOCK" capture-pane -p >&2 || true
  die "timed out waiting for: $pattern"
}

# Launch an interactive zsh in a real terminal, started inside the marker dir,
# under the shared CI pane conventions (see zsh_pane_cmd in tmux_e2e_helpers.sh).
tmux -L "$SOCK" new-session -d -x 200 -y 50 -c "$WORK" "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# 1) Starship is the live prompt (not the fallback): its [time] module renders a
#    timestamp the fallback PROMPT never produces.
wait_for '[0-9]{4}-[0-9]{2}-[0-9]{2}'
echo "== Starship prompt is live (time module rendered) =="

# 2) The [directory] module reflects $PWD — the marker dir name is on screen.
wait_for 'starship_e2e_zone'
echo "== directory module reflects \$PWD =="

# 3) `px` round-trips STARSHIP_CONFIG main <-> sub. STARSHIP_CONFIG starts unset,
#    so the first px selects the sub config and the second returns to the main
#    one. Each value is printed with a unique marker so the assertion can only
#    match the line we just produced, not earlier scrollback.
# shellcheck disable=SC2016  # single-quoted on purpose: zsh in the pane must
# expand $STARSHIP_CONFIG and run px, not this shell.
tmux -L "$SOCK" send-keys 'px; print "__CFG1__${STARSHIP_CONFIG}"' Enter
wait_for '__CFG1__.*/starship_sub\.toml'
echo "== px (1st) selected the sub config =="

# shellcheck disable=SC2016
tmux -L "$SOCK" send-keys 'px; print "__CFG2__${STARSHIP_CONFIG}"' Enter
wait_for '__CFG2__.*/starship\.toml'
echo "== px (2nd) returned to the main config =="

tmux -L "$SOCK" send-keys C-c
echo "PASS"
