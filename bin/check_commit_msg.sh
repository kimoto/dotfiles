#!/bin/bash

# Validate a commit message against Conventional Commits
# (type(scope)!: description), type in {feat,fix,chore,docs,refactor,ci,test,
# revert}. Single source of truth shared by CI checks and the lefthook
# commit-msg hook, so the rule lives in ONE place instead of inline YAML.
#
# Usage: check_commit_msg.sh <path-to-commit-msg-file>
# Only the first line (the subject) is checked. Merge/Revert/fixup!/squash!
# subjects that git generates are exempt.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $(basename "$0") <commit-msg-file>" >&2
    exit 2
fi

msg=$(head -1 "$1")

case "$msg" in
    Merge*|Revert*|"fixup! "*|"squash! "*) exit 0 ;;
esac

if echo "$msg" | grep -qE '^(feat|fix|chore|docs|refactor|ci|test|revert)(\([a-z0-9-]+\))?!?: .+'; then
    exit 0
fi

echo "x Not a valid Conventional Commits message:"
echo "    $msg"
echo "  example: feat(ghostty): add opacity toggle keybind"
echo "  type: feat|fix|chore|docs|refactor|ci|test|revert"
exit 1
