#!/bin/bash
# Interactive end-to-end test for the completion candidate colours in .zshrc.
#
# .zshrc registers
#
#   zstyle -e ':completion:*' list-colors 'reply=( ${(s.:.)LS_COLORS} )'
#
# with `-e` — evaluated at every lookup — because LS_COLORS does not exist yet
# when that line runs: it is exported by the vivid-ls-colors plugin, which
# config/sheldon/plugins.toml loads through zsh-defer, i.e. after the first
# prompt. The plain form (`list-colors ${(s.:.)LS_COLORS}`) captured an empty
# value at load time and every completion candidate was listed uncoloured.
#
# Only a real terminal can prove the candidates come out coloured: the style
# value alone is checked by test/completion_list_colors.bats, but the drawing
# happens in zsh/complist against a tty. So this drives a real pane via tmux
# send-keys + capture-pane -e (`-e` keeps the escape sequences that ARE the
# assertion), the same way the other bin/ci_*_test.sh e2e tests do.
#
# shellcheck disable=SC2016  # send-keys strings are single-quoted on purpose:
# every `$LS_COLORS`/`$(...)` must be evaluated by the zsh inside the pane.
set -euo pipefail

# Shared e2e plumbing: die/need, the brew shellenv, and zsh_pane_cmd.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version) =="

# Distinctive 256-colour codes rather than a real vivid palette: they survive
# tmux's capture as literal "38;5;<n>" so the assertion names exactly which
# candidate got which colour, instead of "something was coloured".
DIR_COLOR='38;5;196'
TXT_COLOR='38;5;46'
PALETTE="di=$DIR_COLOR:*.txt=$TXT_COLOR"

# Two candidates with no common prefix, so one TAB has to draw a list.
TMP="$(mktemp -d)"
WORK="$TMP/work"
mkdir -p "$WORK/zdir"
: >"$WORK/qfile.txt"

SOCK="ci_complcolor_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

# capture-pane -e keeps the SGR sequences; everything this test asserts on is
# an escape sequence, so the -e variant is used throughout. Same 15s default and
# rationale as wait_for_pane in tmux_e2e_helpers.sh (which captures without -e).
wait_for_esc() {
  local pattern="$1" tries="${2:-150}" i=0
  while [ "$i" -lt "$tries" ]; do
    if tmux -L "$SOCK" capture-pane -p -e 2>/dev/null | grep -qE "$pattern"; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  echo "---- pane contents at timeout (escapes shown as <ESC>) ----" >&2
  tmux -L "$SOCK" capture-pane -p -e 2>/dev/null | sed 's/\x1b/<ESC>/g' >&2 || true
  die "timed out waiting for: $pattern"
}

tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# 0) Shell is live.
tmux -L "$SOCK" send-keys 'echo __COMPL_READY__$((6 * 7))' Enter
wait_for_esc '__COMPL_READY__42'
echo "== shell live =="

# 1) Export the palette AFTER startup — the ordering under test. A style
#    captured at .zshrc time cannot see this; a `zstyle -e` body re-read at
#    lookup time can.
#
#    Made readonly in the same command, which is what keeps this test honest:
#    the real vivid-ls-colors plugin also exports LS_COLORS, from a zsh-defer
#    task, at a moment nothing here controls. Readonly turns a late write into
#    a failed assignment instead of a silent palette swap under the assertion
#    below — which is exactly what the first version of this test measured,
#    reporting a failure the shell had not actually made.
#
#    Waiting for the deferred queue instead does not work: a probe task queued
#    from the command line after startup never ran while the pane sat idle for
#    15s in CI, so there is nothing to poll on.
#
#    The read-back marker is spelled `$((6 * 7))` and matched as `42` because
#    capture-pane sees the echoed command line as well as its output: a marker
#    that appears literally in what is typed matches instantly and proves
#    nothing. Same trick the other e2e tests here use.
tmux -L "$SOCK" send-keys "export LS_COLORS='$PALETTE'; typeset -gr LS_COLORS" Enter
tmux -L "$SOCK" send-keys 'print __LSC_$((6 * 7))__$LS_COLORS' Enter
wait_for_esc "__LSC_42__di=$DIR_COLOR"
echo "== LS_COLORS exported after .zshrc, as the deferred plugin would =="

# 2) TAB on an ambiguous argument draws the candidate list. Each entry must
#    carry its LS_COLORS colour: the .txt file green, the directory red.
tmux -L "$SOCK" send-keys "builtin cd '$WORK'" Enter
tmux -L "$SOCK" send-keys 'ls '
tmux -L "$SOCK" send-keys Tab
wait_for_esc 'qfile\.txt'
wait_for_esc "\[${TXT_COLOR}m[^m]*qfile\.txt"
wait_for_esc "\[${DIR_COLOR}m[^m]*zdir"
echo "== both candidates drawn in their LS_COLORS colours =="

echo "PASS"
