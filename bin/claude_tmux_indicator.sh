#!/bin/sh
# Claude Code hook handler (registered by bin/install_claude_tmux_hooks.sh):
# color this pane's border and window-status entry by Claude's state.
#   waiting = red (blocked on the user) / done = yellow (finished) / clear
# Writes only the pane option @claude_state + border override; the window
# color @claude_color is recomputed server-side from @claude_win_color (see
# .tmux.conf) — atomic, so concurrent sessions in one window can't race.
# Outside tmux this is a silent no-op: a hook must never break a session.
set -eu

RED="#dc322f"
YELLOW="#b58900"

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0

color=""
case "${1:-}" in
  waiting) state=waiting color="$RED" ;;
  done)    state='done'  color="$YELLOW" ;;
  clear)   state="" ;;
  *) echo "usage: $0 waiting|done|clear" >&2; exit 2 ;;
esac

if [ -n "$state" ]; then
  tmux set-option -p -t "$TMUX_PANE" @claude_state "$state" \; \
       set-option -p -t "$TMUX_PANE" pane-border-style "fg=$color" \; \
       set-option -p -t "$TMUX_PANE" pane-active-border-style "fg=$color,bold" \; \
       set-option -wF -t "$TMUX_PANE" @claude_color '#{E:@claude_win_color}' \; \
       refresh-client -S 2>/dev/null || true
else
  # clear fires on every tool call: exit early when nothing is set.
  cur="$(tmux display-message -p -t "$TMUX_PANE" '#{@claude_state}' 2>/dev/null || true)"
  [ -n "$cur" ] || exit 0
  tmux set-option -pu -t "$TMUX_PANE" @claude_state \; \
       set-option -pu -t "$TMUX_PANE" pane-border-style \; \
       set-option -pu -t "$TMUX_PANE" pane-active-border-style \; \
       set-option -wF -t "$TMUX_PANE" @claude_color '#{E:@claude_win_color}' \; \
       refresh-client -S 2>/dev/null || true
fi
