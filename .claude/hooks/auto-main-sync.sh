#!/bin/bash
# At SessionEnd: when the current branch's PR has merged and the working tree is
# clean, return to main, pull, and delete the merged branch — so the just-merged
# work lands in the local checkout. Fires once when the session ends, never
# mid-turn. A dirty tree (or a still-open PR) only prints a reminder; the
# checkout is left untouched so nothing is switched out from under unsaved work.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v gh >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

current_branch=$(git branch --show-current 2>/dev/null) || exit 0
[[ -z "$current_branch" || "$current_branch" == "main" ]] && exit 0

pr_info=$(gh pr view "$current_branch" --json state,number --jq '"#\(.number) \(.state)"' 2>/dev/null) || exit 0

case "$pr_info" in
  *MERGED*)
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      echo "[reminder] PR $pr_info for '$current_branch' merged, but the working tree is dirty — commit/stash, then: git switch main && git pull"
      exit 0
    fi
    if git switch main >/dev/null 2>&1 && git pull --ff-only >/dev/null 2>&1; then
      git branch -d "$current_branch" >/dev/null 2>&1 || true
      echo "[auto-main-sync] PR $pr_info merged — switched to main, pulled, deleted '$current_branch'"
    else
      echo "[reminder] PR $pr_info merged, but auto-switch failed — run: git switch main && git pull"
    fi
    ;;
  *OPEN*)
    echo "[reminder] PR $pr_info for '$current_branch' still open — switch to main after CI passes"
    ;;
esac
