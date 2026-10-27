#!/bin/sh
# prefix + G: pick a repo in a popup and go to its window — the first window in
# this session with a pane inside the repo, or else a new shell window there.
# Works from any pane, including one where Claude Code holds the prompt.
set -eu

dir=$("$(dirname "$0")/ghq_pick.sh") || exit 0

win=$(tmux list-panes -s -F '#{window_id} #{pane_current_path}' |
	awk -v d="$dir" '{
		id = $1
		sub(/^[^ ]+ /, "")
		if ($0 == d || index($0, d "/") == 1) { print id; exit }
	}')

if [ -n "$win" ]; then
	tmux select-window -t "$win"
else
	tmux new-window -c "$dir"
fi
