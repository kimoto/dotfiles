#!/bin/bash
# At SessionStart: when the checked-out branch's PR has merged, tell the agent
# how to get back to main. Stdout becomes context for the session that is
# starting, which then does the switch itself, in front of the person.
#
# It never switches, pulls or deletes on its own. Several sessions can share one
# checkout, and a hook cannot tell whose branch is checked out — moving HEAD
# here would move it under a session that is still working there.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v gh >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# A linked worktree keeps its own gitdir under the shared .git/worktrees/; the
# primary checkout has the two paths equal.
# Both paths go through `pwd -P` so a symlinked TMPDIR can't make the primary
# checkout look like a worktree.
in_linked_worktree() {
  local git_dir common_dir
  git_dir=$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  [[ "$git_dir" != "$common_dir" ]]
}

current_branch=$(git branch --show-current 2>/dev/null) || exit 0
[[ -z "$current_branch" || "$current_branch" == "main" ]] && exit 0

# The one network call; it only runs off main, and starting a session on a
# feature branch is rare once sessions live in worktrees.
pr_info=$(gh pr view "$current_branch" --json state,number --jq '"#\(.number) \(.state)"' 2>/dev/null) || exit 0
[[ "$pr_info" == *MERGED* ]] || exit 0

if in_linked_worktree; then
  echo "[merged-branch] PR $pr_info for '$current_branch' merged. This worktree is done;" \
    "from the main checkout: git worktree remove $PWD && git branch -d $current_branch"
  exit 0
fi
echo "[merged-branch] PR $pr_info for '$current_branch' merged, and this is the shared main checkout." \
  "Before new work, check \`git status\` is clean, then: git switch main && git pull --ff-only" \
  "&& git branch -d $current_branch. Do new work in a worktree, not here."
