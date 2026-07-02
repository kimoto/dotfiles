#!/bin/bash
# End-to-end test for the Claude Code tmux state indicator
# (bin/claude_tmux_indicator.sh + the @claude_color conditionals in
# .tmux.conf). Runs the real hook script against a real tmux server, then
# asserts both layers: the options the script sets (window @claude_color, the
# per-pane border overrides) and how the status-line formats render them —
# expanded with `display-message -p`, exactly as tmux evaluates them when
# drawing. Covers: waiting (red), done (yellow), red-beats-yellow priority
# across panes in one window, clear (back to defaults), and the outside-tmux
# no-op.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

# The ✳ marker is multibyte; under a non-UTF-8 locale (bare CI shells) tmux
# renders it as '_' and the glyph assertions below would miss it.
export LC_ALL=C.UTF-8 LANG=C.UTF-8

CONF="$(tmux_conf_path)"
echo "== conf under test: $CONF =="

RED="#dc322f"
YELLOW="#b58900"

SOCK="ci_claude_ind_$$"
SESS="INDCHECK"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" -f "$CONF" new-session -d -s "$SESS" -x 200 -y 50 || die "failed to start tmux"

SOCK_PATH="$(tmux -L "$SOCK" display-message -p '#{socket_path}')"
PANE1="$(tmux -L "$SOCK" display-message -p '#{pane_id}')"

# Run the hook script the way Claude Code does: as a plain child process that
# only knows it is inside tmux via $TMUX / $TMUX_PANE.
ind() { TMUX="$SOCK_PATH,0,0" TMUX_PANE="$2" "$DIR/claude_tmux_indicator.sh" "$1"; }

opt() { tmux -L "$SOCK" show-options -gqv "$1"; }
win_color() { tmux -L "$SOCK" show-options -wqv -t "$PANE1" @claude_color; }
pane_border() { tmux -L "$SOCK" show-options -pqv -t "$1" pane-border-style; }
expand() { tmux -L "$SOCK" display-message -p "$1" 2>/dev/null | tr -d '\000'; }

# 1) waiting -> red window option, red pane border, red + marker in both
#    window-status formats.
ind waiting "$PANE1"
[ "$(win_color)" = "$RED" ] || die "waiting: window @claude_color expected $RED, got '$(win_color)'"
pane_border "$PANE1" | grep -qF "$RED" || die "waiting: pane-border-style not overridden to $RED"
expand "$(opt window-status-format)" | grep -qF "$RED" \
  || die "waiting: window-status-format did not render $RED"
expand "$(opt window-status-current-format)" | grep -qF "$RED" \
  || die "waiting: window-status-current-format did not render $RED"
expand "$(opt window-status-current-format)" | grep -qF "✳" \
  || die "waiting: window-status-current-format did not render the ✳ marker"
echo "== waiting colors the pane border and window entry red =="

# 2) done -> same pane flips to yellow.
ind 'done' "$PANE1"
[ "$(win_color)" = "$YELLOW" ] || die "done: window @claude_color expected $YELLOW, got '$(win_color)'"
pane_border "$PANE1" | grep -qF "$YELLOW" || die "done: pane-border-style not overridden to $YELLOW"
echo "== done colors it yellow =="

# 3) two panes in one window: a waiting (red) pane outranks a done (yellow)
#    one; clearing the red pane falls back to yellow, not to default.
tmux -L "$SOCK" split-window -d -t "$SESS"
PANE2="$(tmux -L "$SOCK" list-panes -t "$SESS" -F '#{pane_id}' | grep -v "^$PANE1\$" | head -n1)"
ind waiting "$PANE2"
[ "$(win_color)" = "$RED" ] || die "priority: red pane should win over yellow, got '$(win_color)'"
ind clear "$PANE2"
[ "$(win_color)" = "$YELLOW" ] || die "priority: clearing the red pane should fall back to yellow"
[ -z "$(pane_border "$PANE2")" ] || die "clear: pane 2 border override should be gone"
echo "== red beats yellow across panes; clear recomputes the window color =="

# 4) clear on the last flagged pane -> option unset, border override gone,
#    formats back to the defaults (inactive gray, no marker).
ind clear "$PANE1"
[ -z "$(win_color)" ] || die "clear: window @claude_color should be unset, got '$(win_color)'"
[ -z "$(pane_border "$PANE1")" ] || die "clear: pane 1 border override should be gone"
expand "$(opt window-status-format)" | grep -qF "#586e75" \
  || die "clear: window-status-format did not fall back to the default fg"
if expand "$(opt window-status-current-format)" | grep -qF "✳"; then
  die "clear: the ✳ marker is still rendered"
fi
echo "== clear restores the default colors =="

# 5) outside tmux the hook is a silent no-op (Claude Code also runs in plain
#    terminals; the hook must not fail there).
out="$(env -u TMUX -u TMUX_PANE "$DIR/claude_tmux_indicator.sh" waiting 2>&1)" \
  || die "outside tmux: expected exit 0"
[ -z "$out" ] || die "outside tmux: expected no output, got '$out'"
echo "== outside tmux it is a silent no-op =="

echo "PASS"
