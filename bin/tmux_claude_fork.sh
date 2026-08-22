#!/bin/sh
# prefix + A: fork this pane's Claude Code session into a float.
#
# Drop the mirroring below and nothing breaks — it just costs. The prompt cache
# matches on an exact prefix, so any flag or binary that shifts the system
# prompt makes the fork re-send everything: 117k created, 0 read.
set -eu

pane="${1:-${TMUX_PANE:-}}"
CLAUDE="$HOME/.local/bin/claude"
STATE_DIR="${TMUX_ASSISTANT_RESURRECT_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tmux-assistant-resurrect}"

die() {
	# run-shell has nowhere to print, so failures must reach the status line.
	tmux display-message "claude fork: $1"
	exit 0
}

[ -n "$pane" ] || die "no pane"
[ -x "$CLAUDE" ] || die "$CLAUDE not found"

session=""
cwd=""
pid=""
statefile=""
for f in "$STATE_DIR"/claude-*.json; do
	[ -f "$f" ] || continue
	p=${f##*/claude-}
	p=${p%.json}
	kill -0 "$p" 2>/dev/null || continue
	match=$(jq -r --arg p "$pane" \
		'select(.env.tmux_pane == $p) | "\(.session_id) \(.cwd)"' "$f" 2>/dev/null) || continue
	[ -n "$match" ] || continue
	session=${match%% *}
	cwd=${match#* }
	pid=$p
	statefile=$f
	break
done

[ -n "$session" ] || die "no live claude session in $pane"

# A day-old parent still runs the image it started on, while the symlink has
# moved on (seen: 2.1.237 beside 2.1.239).
image=$(lsof -p "$pid" -a -d txt -Fn 2>/dev/null |
	sed -n 's|^n\(.*/claude/versions/[^/]*\)$|\1|p' | head -1)
if [ -n "$image" ] && [ -x "$image" ]; then
	CLAUDE=$image
fi

cmd="$CLAUDE --fork-session --resume $session"

args=$(ps -o args= -p "$pid" 2>/dev/null || true)
mode=$(printf '%s\n' "$args" | sed -n 's/.*--permission-mode[= ]\{1,\}\([a-zA-Z]\{1,\}\).*/\1/p')
if [ -n "$mode" ]; then
	cmd="$cmd --permission-mode $mode"
fi
model=$(printf '%s\n' "$args" | sed -n 's/.*--model[= ]\{1,\}\([^ ]\{1,\}\).*/\1/p')
if [ -n "$model" ]; then
	cmd="$cmd --model $model"
fi

# ListAgents shows no parentage. Geometry mirrors .tmux.conf — change both.
new=$(tmux new-pane -x 99% -y 70% -X 0% -Y 0% -P -F '#{pane_id}' -c "$cwd" "$cmd")
tmux set-option -p -t "$new" @claude_fork_parent "$pane"

# The cache expires after an hour, so warn when the parent is past it. mtime
# lies — 35m where the last real exchange was 143m old, because a resumed or
# busy parent rewrites the transcript without an API call.
transcript=$(jq -r '.transcript_path // empty' "$statefile" 2>/dev/null || true)
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	stamp=$(tail -400 "$transcript" 2>/dev/null |
		jq -rR 'fromjson? | select(.message.usage != null) | .timestamp' 2>/dev/null |
		tail -1)
	idle=$(printf '%s' "$stamp" |
		jq -rR 'sub("\\.[0-9]+Z$";"Z") | fromdateiso8601 | ((now - .) / 60 | floor)' 2>/dev/null || true)
	case $idle in
	[0-9]*)
		if [ "$idle" -gt 55 ]; then
			tmux display-message \
				"claude fork: parent idle ${idle}m — its cache has expired, so this fork re-sends the whole context"
		fi
		;;
	esac
fi
