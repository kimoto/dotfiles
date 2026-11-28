#!/bin/bash

# One colour scheme for routine labels in every repo a routine opens PRs in.
#
#   routine_labels.sh [--dry-run] [--repo OWNER/REPO]... [NAME]...
#
# Creates `routine` and each NAME (e.g. routine:test-sweep) where missing, and
# recolours every existing `routine` / `routine:*` label to the scheme below.
# Without --repo it works on the repo of the current directory. Idempotent:
# a label already in the right colour is left alone.
#
# Why a script: a label that an agent adds without creating it first is
# created by GitHub in grey, and a hand-made one gets whatever colour that day
# picked, so the same routine showed up in three colours across repos. The
# skills call this before labelling, so a new routine name starts in colour.

set -euo pipefail

# The parent label stands out; the per-routine ones are a lighter shade of the
# same hue so the pair reads as one family. Purple, because GitHub's own UI
# (links, the default label) is blue.
colour_for() {
    case "$1" in
        routine) echo 5319e7 ;;
        routine:*) echo d4c5f9 ;;
        *) return 1 ;;
    esac
}

usage() {
    sed -n '5p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

dry_run=false
repos=()
names=(routine)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        --repo)
            [ "$#" -ge 2 ] || usage
            repos+=("$2")
            shift
            ;;
        -h | --help) usage ;;
        -*) usage ;;
        *)
            colour_for "$1" >/dev/null || {
                echo "routine_labels: not a routine label: $1" >&2
                exit 2
            }
            names+=("$1")
            ;;
    esac
    shift
done
# gh fills {owner}/{repo} from the current directory's remote.
[ "${#repos[@]}" -gt 0 ] || repos=("{owner}/{repo}")

run() {
    $dry_run || "$@" >/dev/null
}

for repo in "${repos[@]}"; do
    existing=$(gh api --paginate "repos/$repo/labels?per_page=100" \
        --jq '.[] | select(.name == "routine" or (.name | startswith("routine:"))) | "\(.name)\t\(.color)"')

    for name in "${names[@]}"; do
        if ! cut -f1 <<<"$existing" | grep -qxF "$name"; then
            colour=$(colour_for "$name")
            echo "$repo: create $name $colour"
            run gh api -X POST "repos/$repo/labels" -f name="$name" -f color="$colour"
        fi
    done

    while IFS=$'\t' read -r name colour; do
        [ -n "$name" ] || continue
        want=$(colour_for "$name")
        [ "$colour" = "$want" ] && continue
        echo "$repo: recolour $name $colour -> $want"
        run gh api -X PATCH "repos/$repo/labels/$(jq -rn --arg n "$name" '$n | @uri')" -f color="$want"
    done <<<"$existing"
done
