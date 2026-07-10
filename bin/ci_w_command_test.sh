#!/bin/bash
# Interactive end-to-end test for the `w` worktree-jump command in .zshrc.
#
#   w() {
#     local dir=$(git worktree list | fzf --preview '' --query="$*" | awk '{print $1}')
#     test -z "$dir" || cd "$dir"
#   }
#
# i.e. `git worktree list` -> fzf (with the `$*` argument prefilled as the
# query) -> cd into the first field (the worktree path) of the selection. Three
# things can only be proven by driving it for real, in a terminal:
#   1. the worktree list is piped into fzf and the function argument pre-filters
#      it (`--query`);
#   2. selecting cd's into the chosen worktree's path (the `awk '{print $1}'`
#      slice); and
#   3. aborting (no match, or Esc) leaves $PWD put.
#
# Like ci_g_command_test.sh this drives a real terminal via tmux send-keys +
# capture-pane (the TUI analogue of a browser e2e). fzf and git are real; a
# throwaway git repo with two linked worktrees is the hermetic fixture, so the
# test needs no network and no external checkouts.
#
# shellcheck disable=SC2016  # send-keys strings are single-quoted on purpose:
# every `$PWD`/`$(...)` must be evaluated by the zsh inside the pane, not here.
set -euo pipefail

# Shared e2e plumbing: die/need, the brew shellenv, zsh_pane_cmd, wait_*_pane.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
need git
command -v fzf >/dev/null 2>&1 || die "fzf not installed (w pipes git worktree list into fzf)"
command -v awk >/dev/null 2>&1 || die "awk not installed (w slices out the worktree path)"
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version | head -1), $(fzf --version), $(git --version) =="

# ---------------------------------------------------------------------------
# Hermetic fixture: a real git repo (MAIN) with two linked worktrees. The dirs
# and branches carry unique markers so a query narrows fzf to exactly one row
# and the cd assertion is unambiguous about which worktree we landed in.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
MAIN="$TMP/main"
WT_ALPHA="$TMP/wt-wtalpha"
WT_BETA="$TMP/wt-wtbeta"

git -c init.defaultBranch=main init -q "$MAIN"
(
  cd "$MAIN"
  # -c commit.gpgsign=false: the repo's own ~/.gitconfig sets commit.gpgsign=true,
  # but CI runners have no secret key, so an unqualified commit dies with exit 128.
  git -c user.email=ci@example.com -c user.name=ci -c commit.gpgsign=false \
    commit -q --allow-empty -m init
  git worktree add -q -b wtalpha "$WT_ALPHA"
  git worktree add -q -b wtbeta "$WT_BETA"
)

SOCK="ci_w_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

# Launch an interactive zsh in a real terminal under the shared CI pane
# conventions (see zsh_pane_cmd in tmux_e2e_helpers.sh).
tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# 0) Shell is live.
tmux -L "$SOCK" send-keys 'echo __W_READY__$((6 * 7))' Enter
wait_for_pane "$SOCK" "__W_READY__42"
echo "== shell live =="

# `cd` is aliased to `z` (zoxide) in interactive shells (.zshrc: `alias cd=z`),
# and `z` is defined by `zoxide init zsh` via sheldon. In CI the real zoxide is
# present (Brewfile.basic). For a minimal local run without the sheldon/zoxide
# bootstrap, define a cd-equivalent `z` fallback so w's `cd "$dir"` still
# changes directory (mirrors ci_g_command_test.sh).
tmux -L "$SOCK" send-keys 'command -v z >/dev/null 2>&1 || z() { builtin cd "$@"; }' Enter

# Move into the fixture repo (builtin cd bypasses the z alias) so the
# `git worktree list` inside `w` sees our three worktrees.
tmux -L "$SOCK" send-keys "builtin cd '$MAIN'" Enter
tmux -L "$SOCK" send-keys 'echo __W_CWD__:$PWD' Enter
wait_for_pane "$SOCK" "__W_CWD__:$MAIN"
echo "== in the fixture repo =="

# 1) `w <query>` pipes `git worktree list` into fzf and the argument pre-filters
#    to a single worktree. The query "wtalpha" matches only the wtalpha row;
#    assert on the branch bracket, which only fzf's rendering carries (not the
#    typed command line).
tmux -L "$SOCK" send-keys 'w wtalpha' Enter
wait_for_pane "$SOCK" '\[wtalpha\]'
echo "== fzf opened, query filtered to wtalpha =="

# 2) Selecting (Enter) cd's into the chosen worktree path. The marker carries
#    $PWD so the assertion is unambiguous about which worktree we landed in.
tmux -L "$SOCK" send-keys Enter
tmux -L "$SOCK" send-keys 'echo __W_CD__:$PWD' Enter
wait_for_pane "$SOCK" "__W_CD__:$WT_ALPHA"
echo "== Enter cd'd into the selected worktree =="

# 3) A no-match query aborts (FZF_DEFAULT_OPTS carries --exit-0) and must NOT
#    cd: $PWD stays at the alpha worktree from step 2. A distinct marker avoids
#    matching the earlier line in scrollback.
tmux -L "$SOCK" send-keys 'w zzz_no_such_worktree' Enter
tmux -L "$SOCK" send-keys 'echo __W_NOCD__:$PWD' Enter
wait_for_pane "$SOCK" "__W_NOCD__:$WT_ALPHA"
echo "== no-match abort left \$PWD unchanged (no cd) =="

# 4) Bare `w` (empty query) lists every worktree. Assert the beta worktree —
#    filtered out in step 1 — is present, then abort with Esc and confirm no cd.
tmux -L "$SOCK" send-keys 'w' Enter
wait_for_pane "$SOCK" '\[wtbeta\]'
tmux -L "$SOCK" send-keys Escape
wait_absent_pane "$SOCK" '\[wtbeta\]'   # fzf fully closed before typing again
tmux -L "$SOCK" send-keys 'echo __W_ESC__:$PWD' Enter
wait_for_pane "$SOCK" "__W_ESC__:$WT_ALPHA"
echo "== bare w listed all worktrees; Esc aborted without cd =="

echo "PASS"
