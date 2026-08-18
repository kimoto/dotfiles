#!/bin/bash
# End-to-end test for the status bar and the dynamic window/pane formats. Each
# configured format is expanded with `display-message -p`, which evaluates a
# format string exactly as tmux does when drawing it — so we assert the
# rendering *logic* (conditionals and fields) without brittle pixel capture of
# the status line. Covers: status-left (session), status-right (clock),
# window-status-current-format (#I:#W), automatic-rename-format (its
# panes/title conditional, both branches), and pane-border-format.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
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

# 7) Solarized theme options actually land. The load test only proves the file
#    parses: a stray quote inside one of the version-guarded blocks drops every
#    option after it without any error, so read the values back. Options behind
#    a guard are asserted only on a tmux new enough to have them.
tmux_at_least() {
  local want_major="$1" want_minor="$2" v major minor
  v="$(tmux -V | sed -En 's/^tmux ([0-9]+)\.([0-9]+).*/\1 \2/p')"
  [ -n "$v" ] || return 1
  major="${v% *}"; minor="${v#* }"
  [ "$major" -gt "$want_major" ] ||
    { [ "$major" -eq "$want_major" ] && [ "$minor" -ge "$want_minor" ]; }
}
theme_is() {
  local got; got="$(opt "$1")"
  [ "$got" = "$2" ] || die "$1 expected '$2', got '${got:-<unset>}'"
}
theme_is popup-style "bg=#073642,fg=#839496"
theme_is popup-border-style "fg=#2aa198"
theme_is copy-mode-match-style "bg=#b58900,fg=#002b36"
theme_is copy-mode-current-match-style "bg=#cb4b16,fg=#002b36,bold"
theme_is copy-mode-mark-style "bg=#d33682,fg=#002b36"
echo "== popup and copy-mode search styles are Solarized =="

if tmux_at_least 3 6; then
  theme_is menu-selected-style "bg=#2aa198,fg=#002b36,bold"
  theme_is copy-mode-position-style "bg=#073642,fg=#2aa198"
  theme_is copy-mode-selection-style "bg=#2aa198,fg=#002b36"
  echo "== 3.6+ guarded block applied (menu selection, copy-mode position) =="
else
  echo "== 3.6+ guarded block skipped on $(tmux -V) =="
fi

if tmux_at_least 3 7; then
  theme_is copy-mode-line-number-style "fg=#586e75"
  theme_is copy-mode-current-line-number-style "fg=#b58900,bold"
  echo "== 3.7+ guarded block applied (copy-mode line numbers) =="
else
  echo "== 3.7+ guarded block skipped on $(tmux -V) =="
fi

echo "PASS"
