#!/bin/bash
# PreToolUse hook for Bash calls: refuse a worktree made from the shell and
# point the agent at the EnterWorktree tool instead.
#
# Bash resets its cwd to the project after every command, so a session that
# works in such a worktree through `cd <worktree> && ...` never actually moves:
# Claude, its tmux pane, and so prefix + v / V and bin/claude_tmux_hunk.sh all
# stay on the main checkout and show an empty diff. EnterWorktree moves Claude.
#
# Claude Code sends the tool call as JSON on stdin and reads hookSpecificOutput
# JSON back on stdout; printing nothing lets the call through. Quoted text is
# stripped before matching, so a command that only mentions one stays allowed.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# A double-quoted string holding a $ stays: "$(worktree_new.sh ...)" runs it.
bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"\$]*\"//g")
start='(^|[;&|(]|&&|\|\||\$\()[[:space:]]*'
# git (with any options, e.g. -C <dir>) worktree add, or the W helper's script.
git_add="${start}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)"
helper="${start}([^[:space:]]*/)?worktree_new\.sh([[:space:]]|$)"
if ! printf '%s' "$bare" | grep -qE "$git_add|$helper"; then
  exit 0
fi

jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Make the worktree with the EnterWorktree tool instead, then "
      + "`git switch -c <type>/<short-desc>` inside it; to work in one that already exists, "
      + "call EnterWorktree with its path. A worktree reached through `cd` in Bash leaves "
      + "this session on the main checkout, since Bash resets its directory after every "
      + "command, so the hunk diff beside it shows nothing.")
  }
}'
