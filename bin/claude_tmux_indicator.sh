#!/bin/sh
# Claude Code hook handler: color the tmux pane border and window-status entry
# by Claude's state, so the pane that needs attention is visible at a glance
# from any window.
#
#   claude_tmux_indicator.sh waiting   # red    — blocked on the user (permission / idle)
#   claude_tmux_indicator.sh done      # yellow — finished, ready for the next prompt
#   claude_tmux_indicator.sh clear     # back to normal (prompt submitted, tool resumed, …)
#
# Registered in ~/.claude/settings.json by bin/install_claude_tmux_hooks.sh.
# It sets the window user option @claude_color (rendered by the
# window-status-* formats in .tmux.conf) and overrides the flagged pane's
# border style directly. Outside tmux, or on a tmux too old for per-pane
# options, it is a silent no-op — a hook must never break a Claude session.
set -eu

RED="#dc322f"     # Solarized red: Claude is blocked on the user
YELLOW="#b58900"  # Solarized yellow: Claude finished responding

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

case "${1:-}" in
  waiting) color="$RED" ;;
  done)    color="$YELLOW" ;;
  clear)   color="" ;;
  *) echo "usage: $0 waiting|done|clear" >&2; exit 2 ;;
esac

# tmux calls may fail on old servers (< 3.1: no per-pane options) or when the
# server is already gone; never let that surface as a hook failure.
t() { tmux "$@" 2>/dev/null || true; }

if [ -n "$color" ]; then
  t set-option -p -t "$TMUX_PANE" @claude_pane_color "$color"
  t set-option -p -t "$TMUX_PANE" pane-border-style "fg=$color"
  t set-option -p -t "$TMUX_PANE" pane-active-border-style "fg=$color,bold"
else
  t set-option -pu -t "$TMUX_PANE" @claude_pane_color
  t set-option -pu -t "$TMUX_PANE" pane-border-style
  t set-option -pu -t "$TMUX_PANE" pane-active-border-style
fi

# The window shows the most urgent state left across its panes (red beats
# yellow), so clearing one pane never hides another that still needs input.
panes="$(t list-panes -t "$TMUX_PANE" -F '#{@claude_pane_color}')"
case "$panes" in
  *"$RED"*)    t set-option -w -t "$TMUX_PANE" @claude_color "$RED" ;;
  *"$YELLOW"*) t set-option -w -t "$TMUX_PANE" @claude_color "$YELLOW" ;;
  *)           t set-option -wu -t "$TMUX_PANE" @claude_color ;;
esac
