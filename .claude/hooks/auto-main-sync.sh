#!/bin/bash
# Switch to main automatically when the current branch's PR has been merged.
# Called by SessionStart and Stop hooks in settings.json.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v gh >/dev/null 2>&1 || exit 0

current_branch=$(git branch --show-current 2>/dev/null) || exit 0
[[ -z "$current_branch" || "$current_branch" == "main" ]] && exit 0

# Don't switch with uncommitted changes
git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || exit 0

# Cache PR state for 60s to avoid redundant API calls (Stop fires after every turn)
cache="${TMPDIR:-/tmp}/auto-main-sync-${current_branch//\//_}.cache"
now=$(date +%s)
mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
if (( now - mtime < 60 )); then
  pr_state=$(cat "$cache" 2>/dev/null || echo "")
else
  pr_state=$(gh pr view "$current_branch" --json state --jq '.state' 2>/dev/null) || exit 0
  printf '%s' "$pr_state" > "$cache"
fi

[[ "$pr_state" == "MERGED" ]] || exit 0

echo "[auto-main-sync] PR for '$current_branch' merged — switching to main"
git switch main && git pull --ff-only
rm -f "$cache"
git branch -d "$current_branch" 2>/dev/null || true
echo "[auto-main-sync] Now on main ($(git rev-parse --short HEAD))"
