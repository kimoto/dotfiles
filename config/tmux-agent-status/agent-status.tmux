#!/bin/sh
# tmux-agent-status: which panes hold a coding agent (Claude Code, Codex)
# waiting on you or finished, and a switcher that jumps there first.
# .tmux.conf loads this with run-shell, the way tpm loads a plugin; each
# agent's hooks call scripts/hook.sh. The theme's window-status formats read
# @agent_color, which this keeps in step with the panes.
#   @agent_status_switch_key  key for the switcher popup (default f)
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

# Window color: red if any pane waits, else yellow if any is done (state.sh
# colors). Recomputed when panes move or die, deferred via run-shell -b, and
# the status formats read only the plain @agent_color: evaluating #{P:}
# mid-command or at draw time crashes tmux 3.7.
waiting='#{m:*waiting*,#{P:#{@agent_state}}}'
done='#{m:*done*,#{P:#{@agent_state}}}'
tmux set-option -g @agent_win_color "#{?$waiting,#dc322f,#{?$done,#b58900,}}"
resync='run-shell -b "tmux set-option -wF -t \"#{window_id}\" @agent_color \"##{E:@agent_win_color}\""'
tmux set-hook -ga window-layout-changed "$resync" \; \
     set-hook -ga window-linked "$resync"

# fzf over every pane of every session, with a live preview; switch-client
# accepts a pane target. A popup has no TMUX_PANE of its own, hence asking the
# server which pane is current.
key="$(tmux show-option -gqv @agent_status_switch_key)"
# Only $DIR expands now; the rest runs in the popup's shell.
# shellcheck disable=SC2016
{
  popup='"'"$DIR"'/scripts/switcher.sh" "$(tmux display-message -p "#{pane_id}")"'
  popup="$popup"' | fzf --reverse --prompt="switch> " --preview "tmux capture-pane -ep -t {1}"'
  popup="$popup"' --preview-window "right,60%"'
  popup="$popup"' | { read -r sel; [ -n "$sel" ] && tmux switch-client -t "${sel%%  *}"; }'
}
tmux bind-key -N "Switch to any pane, waiting agent first, then most recent" \
  "${key:-f}" display-popup -E -w 90% -h 70% "$popup"
