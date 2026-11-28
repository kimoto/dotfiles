#!/bin/bash

# Print whether CI must run the e2e jobs for this branch: "false" only when
# every file the branch changes is prose no e2e job reads, "true" otherwise.
# Every doubt answers "true" — an unresolvable base, an empty diff (a push to
# main), a path not on the list — so a broken check costs minutes, never an
# untested merge.
#
# Usage: ci_needs_e2e.sh [base]   (default: origin/main)
# Diffs from the merge base, not the previous push: CI cancels a superseded
# run, so a code push followed by a docs-only push must still run e2e.

set -uo pipefail

base="${1:-origin/main}"

# Markdown is prose to every e2e job, except the files a script parses as data.
is_inert() {
    case "$1" in
        # bin/keys.sh, check_keybindings.sh and keys_command_test.sh parse it.
        KEYBINDINGS.md) return 1 ;;
        *.md) return 0 ;;
        *) return 1 ;;
    esac
}

if ! merge_base="$(git merge-base "$base" HEAD 2>/dev/null)"; then
    echo true
    exit 0
fi

# --no-renames lists both sides of a rename, so code moved into a .md counts.
if ! changed="$(git diff --name-only --no-renames "$merge_base" HEAD)" || [ -z "$changed" ]; then
    echo true
    exit 0
fi

while IFS= read -r path; do
    if ! is_inert "$path"; then
        echo true
        exit 0
    fi
done <<<"$changed"

echo false
