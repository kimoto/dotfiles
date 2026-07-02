#!/bin/bash

# Validate every commit subject in a range against Conventional Commits, using
# the same bin/check_commit_msg.sh the lefthook commit-msg hook runs. This is
# the CI-side net for commits that bypass the local hook (--no-verify, web-UI
# commits, remote sessions without lefthook installed).
#
# Usage: check_commit_msgs_range.sh [range]   (default: origin/main..HEAD)
# On a push to main the default range is empty, so the check is a no-op there.
# Merge/Revert/fixup!/squash! subjects are exempt inside check_commit_msg.sh.

set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
range="${1:-origin/main..HEAD}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

fail=0
while IFS= read -r sha; do
    git log -1 --format=%B "$sha" >"$tmp"
    if ! "$DIR/check_commit_msg.sh" "$tmp"; then
        echo "  in commit $sha" >&2
        fail=1
    fi
done < <(git rev-list "$range")

exit "$fail"
