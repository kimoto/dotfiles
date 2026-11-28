#!/bin/sh
# Color this pane's border and window-status entry by the agent's state.
#   waiting = red (blocked on the user) / done = yellow (finished) / clear
# Writes only the pane option @agent_state + border override; the window
# color @agent_color is recomputed server-side from @agent_win_color (see
# agent-status.tmux) — atomic, so concurrent agents in one window can't race.
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
  tmux set-option -p -t "$TMUX_PANE" @agent_state "$state" \; \
       set-option -p -t "$TMUX_PANE" pane-border-style "fg=$color" \; \
       set-option -p -t "$TMUX_PANE" pane-active-border-style "fg=$color,bold" \; \
       set-option -wF -t "$TMUX_PANE" @agent_color '#{E:@agent_win_color}' \; \
       refresh-client -S 2>/dev/null || true
else
  # clear fires on every tool call: exit early when nothing is set.
  cur="$(tmux display-message -p -t "$TMUX_PANE" '#{@agent_state}' 2>/dev/null || true)"
  [ -n "$cur" ] || exit 0
  tmux set-option -pu -t "$TMUX_PANE" @agent_state \; \
       set-option -pu -t "$TMUX_PANE" pane-border-style \; \
       set-option -pu -t "$TMUX_PANE" pane-active-border-style \; \
       set-option -wF -t "$TMUX_PANE" @agent_color '#{E:@agent_win_color}' \; \
       refresh-client -S 2>/dev/null || true
fi
