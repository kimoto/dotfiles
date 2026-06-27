#!/bin/bash
# End-to-end test for the status bar and the dynamic window/pane formats. Each
# configured format is expanded with `display-message -p`, which evaluates a
# format string exactly as tmux does when drawing it — so we assert the
# rendering *logic* (conditionals and fields) without brittle pixel capture of
# the status line. Covers: status-left (session), status-right (clock),
# window-status-current-format (#I:#W), automatic-rename-format (its
# panes/title conditional, both branches), and pane-border-format.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

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
echo "== formats from: $CONF =="

SOCK="ci_tmux_status_$$"
SESS="STATUSCHECK"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" -f "$CONF" new-session -d -s "$SESS" -x 200 -y 50 || die "failed to start tmux"

# Expand a configured option's format string the way tmux would draw it.
opt() { tmux -L "$SOCK" show-options -gqv "$1"; }
expand() { tmux -L "$SOCK" display-message -p "$1" 2>/dev/null | tr -d '\000'; }

# 1) status-left renders the session name.
expand "$(opt status-left)" | grep -q "$SESS" \
  || die "status-left did not render the session name ($SESS)"
echo "== status-left shows session name =="

# 2) status-right renders today's date (the %F clock field).
today="$(date +%F)"
expand "$(opt status-right)" | grep -q "$today" \
  || die "status-right did not render today's date ($today)"
echo "== status-right shows the clock ($today) =="

# 3) window-status-current-format renders the active window's #I:#W.
cur="$(tmux -L "$SOCK" display-message -p '#I:#W')"
expand "$(opt window-status-current-format)" | grep -qF "$cur" \
  || die "window-status-current-format did not render '$cur'"
echo "== window-status-current-format shows '$cur' =="

# 4) automatic-rename-format: single pane with an explicit title -> the title.
arf="$(opt automatic-rename-format)"
tmux -L "$SOCK" select-pane -T "MYTITLE"
got="$(expand "$arf")"
[ "$got" = "MYTITLE" ] || die "rename-format (1 pane, titled) expected 'MYTITLE', got '$got'"
echo "== automatic-rename-format uses pane_title when single-pane =="

# 5) automatic-rename-format: with a second pane the AND condition fails, so it
#    falls back to the current path's basename (not the title).
tmux -L "$SOCK" split-window -d
base="$(basename "$(tmux -L "$SOCK" display-message -p '#{pane_current_path}')")"
got="$(expand "$arf")"
[ "$got" = "$base" ] || die "rename-format (2 panes) expected basename '$base', got '$got'"
echo "== automatic-rename-format falls back to path basename when split =="

# 6) pane-border-format shows '#<index>: <title>' for the titled pane.
expand "$(opt pane-border-format)" | grep -q "MYTITLE" \
  || die "pane-border-format did not render the pane title"
echo "== pane-border-format renders the pane title =="

echo "PASS"
