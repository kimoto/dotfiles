#!/bin/bash
# Print the commit of the newest successful run of a workflow on main that is
# at least <days> old, or nothing when there is none yet.
#
#   ci/aged_pass.sh <workflow-file> <days> <event>...
#
# `stable` moves only to such a commit. The bootstrap runs daily so a
# breakage shows up within a day, but a commit that has sat on main for a week
# without anyone hitting a problem is worth more than one that passed an hour
# ago: the age is the soak time, the pass is the proof. <event> limits which
# runs count (a cached run proves less than one that installed from scratch).
# Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail

workflow="${1:?usage: aged_pass.sh <workflow-file> <days> <event>...}"
days="${2:?usage: aged_pass.sh <workflow-file> <days> <event>...}"
shift 2
[ "$#" -gt 0 ] || { echo "usage: aged_pass.sh <workflow-file> <days> <event>..." >&2; exit 2; }
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

cutoff="$(date -u -d "-$days days" +%Y-%m-%dT%H:%M:%SZ)"
events="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"

gh api "repos/$repo/actions/workflows/$workflow/runs?branch=main&status=success&per_page=100" \
    --jq "[.workflow_runs[]
           | select(.created_at <= \"$cutoff\")
           | select(.event as \$e | $events | index(\$e))]
          | sort_by(.created_at) | last | .head_sha // empty"
