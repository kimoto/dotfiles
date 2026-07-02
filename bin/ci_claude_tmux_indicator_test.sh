#!/bin/bash
# End-to-end test for the Claude Code tmux state indicator: runs the real
# hook script (bin/claude_tmux_indicator.sh) against a real tmux server
# loaded with the repo .tmux.conf and asserts every layer — pane option and
# border override, the recomputed window color, the resync hooks, and the
# rendered status formats.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
echo "== conf under test: $CONF =="

# Pick an available UTF-8 locale (Linux: C.utf8, macOS: en_US.UTF-8) — under
# a non-UTF-8 locale tmux renders the multibyte ✳ marker as '_'.
UTF8_LOCALE="$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.utf-?8$' | head -n1 || true)"
[ -n "$UTF8_LOCALE" ] || UTF8_LOCALE=en_US.UTF-8
export LC_ALL="$UTF8_LOCALE" LANG="$UTF8_LOCALE"

RED="#dc322f"
YELLOW="#b58900"

SOCK="ci_claude_ind_$$"
SESS="INDCHECK"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" -f "$CONF" new-session -d -s "$SESS" -x 200 -y 50 || die "failed to start tmux"

SOCK_PATH="$(tmux -L "$SOCK" display-message -p '#{socket_path}')"
PANE1="$(tmux -L "$SOCK" display-message -p '#{pane_id}')"

# Run the hook script the way Claude Code does: a plain child process that
# only knows it is inside tmux via $TMUX / $TMUX_PANE.
ind() { TMUX="$SOCK_PATH,0,0" TMUX_PANE="$2" "$DIR/claude_tmux_indicator.sh" "$1"; }

opt() { tmux -L "$SOCK" show-options -gqv "$1"; }
pane_state() { tmux -L "$SOCK" show-options -pqv -t "$1" @claude_state; }
pane_border() { tmux -L "$SOCK" show-options -pqv -t "$1" pane-border-style; }
win_color() { tmux -L "$SOCK" show-options -wqv -t "$1" @claude_color; }
expand_at() { tmux -L "$SOCK" display-message -p -t "$1" "$2" 2>/dev/null | tr -d '\000'; }
# Hook-driven recomputes are deferred (run-shell -b); poll briefly.
wait_win_color() { # <target> <expected> <label>
  local i=0
  while [ "$i" -lt 20 ]; do
    [ "$(win_color "$1")" = "$2" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  die "$3: expected '$2', got '$(win_color "$1")'"
}

# 0) bell must outrank the indicator, and the resync hooks must be registered
#    (window-layout-changed is window-scoped -gw; window-linked is -g).
case "$(opt window-status-format)" in
  *'fg=#{?window_bell_flag,#dc322f,'*) ;;
  *) die "bell: window_bell_flag no longer outranks @claude_color in window-status-format" ;;
esac
echo "== bell keeps priority over the indicator =="
tmux -L "$SOCK" show-hooks -gw | grep -q 'window-layout-changed.*@claude_color' \
  || die "hooks: window-layout-changed does not recompute @claude_color"
tmux -L "$SOCK" show-hooks -g | grep -q 'window-linked.*@claude_color' \
  || die "hooks: window-linked does not recompute @claude_color"
echo "== layout/linked resync hooks are registered =="

# 1) waiting -> red border, red window color, red + ✳ in the formats.
ind waiting "$PANE1"
[ "$(pane_state "$PANE1")" = "waiting" ] \
  || die "waiting: @claude_state expected 'waiting', got '$(pane_state "$PANE1")'"
pane_border "$PANE1" | grep -qF "$RED" || die "waiting: pane-border-style not overridden to $RED"
[ "$(win_color "$PANE1")" = "$RED" ] || die "waiting: window color expected $RED, got '$(win_color "$PANE1")'"
expand_at "$PANE1" "$(opt window-status-format)" | grep -qF "$RED" \
  || die "waiting: window-status-format did not render $RED"
expand_at "$PANE1" "$(opt window-status-current-format)" | grep -qF "$RED" \
  || die "waiting: window-status-current-format did not render $RED"
expand_at "$PANE1" "$(opt window-status-current-format)" | grep -qF "✳" \
  || die "waiting: window-status-current-format did not render the ✳ marker"
echo "== waiting colors the pane border and window entry red =="

# 2) done -> the same pane flips to yellow.
ind 'done' "$PANE1"
[ "$(win_color "$PANE1")" = "$YELLOW" ] \
  || die "done: window color expected $YELLOW, got '$(win_color "$PANE1")'"
pane_border "$PANE1" | grep -qF "$YELLOW" || die "done: pane-border-style not overridden to $YELLOW"
echo "== done colors it yellow =="

# 3) two panes in one window: a waiting (red) pane outranks a done (yellow) one.
tmux -L "$SOCK" split-window -d -t "$SESS"
PANE2="$(tmux -L "$SOCK" list-panes -t "$SESS" -F '#{pane_id}' | grep -v "^$PANE1\$" | head -n1)"
ind waiting "$PANE2"
[ "$(win_color "$PANE1")" = "$RED" ] || die "priority: red pane should win over yellow, got '$(win_color "$PANE1")'"
echo "== red beats yellow across panes =="

# 4) the hooks recompute both windows when a pane moves, so the color follows
#    the pane. join-pane on purpose: tmux 3.7 crashes on ANY break-pane, even
#    with an empty config (verified with a variant matrix in CI).
tmux -L "$SOCK" new-window -d -t "$SESS"
WIN2="$(tmux -L "$SOCK" list-windows -t "$SESS" -F '#{window_id}' | tail -n1)"
tmux -L "$SOCK" join-pane -d -s "$PANE2" -t "$WIN2"
wait_win_color "$PANE1" "$YELLOW" "move: origin window should fall back to yellow"
wait_win_color "$PANE2" "$RED" "move: the red state should follow the moved pane"
echo "== the indicator follows a moved pane; no stale window color =="

# 5) clear -> everything back to the defaults; a second clear is a no-op.
ind clear "$PANE2"
[ -z "$(win_color "$PANE2")" ] || die "clear: pane 2 window color should be empty"
ind clear "$PANE1"
[ -z "$(pane_state "$PANE1")" ] || die "clear: @claude_state should be unset"
[ -z "$(pane_border "$PANE1")" ] || die "clear: pane 1 border override should be gone"
expand_at "$PANE1" "$(opt window-status-format)" | grep -qF "#586e75" \
  || die "clear: window-status-format did not fall back to the default fg"
if expand_at "$PANE1" "$(opt window-status-current-format)" | grep -qF "✳"; then
  die "clear: the ✳ marker is still rendered"
fi
ind clear "$PANE1" || die "clear: repeated clear should stay exit 0"
echo "== clear restores the default colors =="

# 6) outside tmux the hook is a silent no-op.
out="$(env -u TMUX -u TMUX_PANE "$DIR/claude_tmux_indicator.sh" waiting 2>&1)" \
  || die "outside tmux: expected exit 0"
[ -z "$out" ] || die "outside tmux: expected no output, got '$out'"
echo "== outside tmux it is a silent no-op =="

echo "PASS"
