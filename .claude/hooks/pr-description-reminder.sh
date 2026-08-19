#!/bin/bash
# PostToolUse hook for Bash calls: after a push, remind the agent to bring the
# PR description in line with what was just pushed.
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

jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("A git push just ran. If the pushed branch has an open pull request, "
      + "update that PR description (via the GitHub PR update tool) to reflect what was just "
      + "pushed: a short summary of the changes and current status.")
  }
}'
