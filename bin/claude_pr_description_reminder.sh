#!/bin/bash
# Claude Code PostToolUse hook for Bash calls (registered in every repo by
# bin/install_claude_pr_hooks.sh, and by settings-cloud.json in a container):
# after a push, remind the agent that the PR description may no longer hold.
#
# Claude Code sends the tool call as JSON on stdin and reads hookSpecificOutput
# JSON back on stdout; printing nothing means "no comment". Quoted text is
# stripped before matching, so a command that only mentions a push — a grep
# pattern, an echo — leaves the hook silent.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Drop quoted strings, then look for git (with any options, e.g. -C <dir>)
# followed by the push subcommand at the start of a command in the line.
bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
if ! printf '%s' "$bare" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'; then
  exit 0
fi

# What a description may hold lives in one place, the pull-requests rule every
# session already loads; the reminder only points there, so the two never drift.
jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("A git push just ran. If the pushed branch has an open pull request, "
      + "re-check its title and body against ~/.claude/rules/dotfiles/pull-requests.md "
      + "and fix what this push made untrue.")
  }
}'
