#!/usr/bin/env bash
# Stop hook: tell the agent what is still uncommitted, untracked, or unpushed,
# at the point a session looks like it is ending.
#
# Silent when: the cwd is not a git repo / all three counts are zero / the
# counts have not changed since the last time this (session, repo) pair was
# told. Without that last check the same notice repeats after every response
# until the tree is clean, which reads as a loop and gets ignored.
#
# The counts go back as hookSpecificOutput.additionalContext, which Claude Code
# injects into the agent's context rather than printing to the user.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
[ -z "$session_id" ] && session_id="nosession"

status_lines="$(git status --porcelain 2>/dev/null)"
untracked="$(printf '%s\n' "$status_lines" | grep -c '^??')"
uncommitted="$(printf '%s\n' "$status_lines" | grep -v '^??' | grep -c '.')"

unpushed=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  unpushed="$(git log '@{u}..HEAD' --oneline 2>/dev/null | wc -l | tr -d ' ')"
else
  # No upstream = a branch that has never been pushed. Reporting 0 here would
  # stay silent about the state that is easiest to lose, so count against the
  # default branch instead.
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  if git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
    unpushed="$(git log "$base..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')"
  fi
fi

if [ "$untracked" -eq 0 ] && [ "$uncommitted" -eq 0 ] && [ "$unpushed" -eq 0 ]; then
  exit 0
fi

repo_id="$(git rev-parse --show-toplevel 2>/dev/null | tr '/' '_')"
cache_dir="$HOME/.claude/hooks/.state-cache"
mkdir -p "$cache_dir"
cache_file="${cache_dir}/${session_id}${repo_id}.state"

state="${uncommitted}:${untracked}:${unpushed}"
prev_state=""
[ -f "$cache_file" ] && prev_state="$(cat "$cache_file")"

if [ "$state" = "$prev_state" ]; then
  exit 0
fi
printf '%s\n' "$state" > "$cache_file"

msg="git leftovers: ${uncommitted} uncommitted, ${untracked} untracked, ${unpushed} unpushed"
jq -n --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}, suppressOutput: true}'
