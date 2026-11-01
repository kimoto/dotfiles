#!/bin/sh
# Find a Claude Code session by words said in it, and resume it where it ran.
#
# `/resume` searches titles and summaries, one project at a time; this reads
# every transcript of every project. It reads them all on each call, so it
# slows as they pile up; Claude Code deletes them after cleanupPeriodDays.
set -eu

if [ $# -eq 0 ]; then
	echo "usage: ${0##*/} <words from the conversation>" >&2
	exit 2
fi
phrase=$*
root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
CLAUDE="$HOME/.local/bin/claude"
# fzf on more rows than a screen only scrolls; the newest are the likely ones.
limit=50

# A subagent's transcript sits one level deeper and cannot be resumed alone.
files=$(find "$root" -mindepth 2 -maxdepth 2 -name '*.jsonl' \
	-exec grep -l -i -F -e "$phrase" {} + 2>/dev/null || true)
if [ -z "$files" ]; then
	echo "no session mentions: $phrase" >&2
	exit 1
fi

escaped=$(printf '%s' "$phrase" | sed 's/[][\\.*^$+?(){}|/]/\\&/g')
context=".{0,40}$escaped.{0,40}"

pick=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 ls -t | head -n "$limit" |
	while IFS= read -r f; do
		cwd=$(grep -o -m1 '"cwd":"[^"]*"' "$f" | head -1 | sed 's/^"cwd":"//; s/"$//')
		[ -n "$cwd" ] || continue
		hit=$(grep -o -i -m1 -E -e "$context" "$f" | head -1)
		when=$(grep -o '"timestamp":"[^"]*"' "$f" | tail -1 | cut -c14-29 | tr T ' ')
		printf '%s\t%s\t%s\t%s\n' "$(basename "$f" .jsonl)" "$when" "$cwd" "$hit"
	done | fzf --delimiter='\t' --with-nth=2.. --no-sort --prompt='session> ') || exit 0

session=$(printf '%s\n' "$pick" | cut -f1)
cwd=$(printf '%s\n' "$pick" | cut -f3)
# --resume looks the session up under the directory it is started in.
if [ ! -d "$cwd" ]; then
	echo "$cwd is gone (a removed worktree?); recreate it, then: claude --resume $session" >&2
	exit 1
fi
cd "$cwd"
exec "$CLAUDE" --resume "$session"
