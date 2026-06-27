#!/bin/bash
# At SessionEnd: remind the user to switch to main if their branch's PR has merged.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v gh >/dev/null 2>&1 || exit 0

current_branch=$(git branch --show-current 2>/dev/null) || exit 0
[[ -z "$current_branch" || "$current_branch" == "main" ]] && exit 0

pr_info=$(gh pr view "$current_branch" --json state,number --jq '"#\(.number) \(.state)"' 2>/dev/null) || exit 0

case "$pr_info" in
  *MERGED*)
    echo "[reminder] PR $pr_info for '$current_branch' — run: git switch main && git pull"
    ;;
  *OPEN*)
    echo "[reminder] PR $pr_info for '$current_branch' still open — switch to main after CI passes"
    ;;
esac
