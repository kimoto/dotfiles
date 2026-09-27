#!/bin/bash

# GitHub Actions minutes for private repos: will this month fit the plan?
#
#   gh_actions_cost.sh forecast [OWNER]        month-end projection; exit 1 = warn
#   gh_actions_cost.sh breakdown OWNER/REPO [SINCE]
#                                              billed vs actual per workflow/job
#
# Public repos are free, so only private ones count. Private-repo jobs are
# billed per job, each rounded UP to a whole minute: a 5-second job costs 1
# minute, and six 30-second jobs cost 6 where one 3-minute job costs 3.
# `breakdown` shows that rounding as "waste", which is where the minutes go.
#
# Why forecast exists: GitHub mails at 90% and 100% of included minutes, but
# by 90% the month is already lost (Sep 2026: 90% on the 22nd). A linear
# projection from full days so far says the same thing much earlier.
#
# Tests feed data through GH_ACTIONS_COST_USAGE_JSON / _REPOS_JSON /
# _JOBS_JSON (files) and GH_ACTIONS_COST_TODAY (YYYY-MM-DD) instead of the API.

set -euo pipefail

# Pro plan. Change here if the plan changes, never per call: a threshold
# passed on the command line is a threshold every caller picks differently.
INCLUDED_MINUTES=3000
# Warn only when the projection says the plan will be paid for. A normal month
# sits near 90%, so a lower bar warns nearly every day, and a warning that is
# always on goes unread like the mails did. At 100 it still fired on Sep 7.
WARN_PERCENT=100
# Included minutes are counted in Linux-minute equivalents; grossAmount at the
# Linux rate converts other runners (Windows 2x, macOS 10x) the same way.
LINUX_RATE=0.006

usage() {
    sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

die() {
    echo "gh_actions_cost: $*" >&2
    exit 2
}

today() { echo "${GH_ACTIONS_COST_TODAY:-$(date -u +%Y-%m-%d)}"; }

fetch_usage() { # $1 owner, $2 YYYY-MM-DD
    if [ -n "${GH_ACTIONS_COST_USAGE_JSON:-}" ]; then
        cat "$GH_ACTIONS_COST_USAGE_JSON"
        return
    fi
    local y m
    y=${2%%-*}
    m=$((10#$(echo "$2" | cut -d- -f2)))
    gh api "/users/$1/settings/billing/usage?year=$y&month=$m"
}

fetch_repos() { # $1 owner
    if [ -n "${GH_ACTIONS_COST_REPOS_JSON:-}" ]; then
        cat "$GH_ACTIONS_COST_REPOS_JSON"
        return
    fi
    gh repo list "$1" --limit 1000 --json name,isPrivate
}

forecast() {
    local owner=${1:-$(gh api user --jq .login)} day usage repos out
    day=$(today)
    # Any failure exits 2, never 1: 1 means WARN, and a broken check that
    # reads as a warning gets ignored the same way a quiet one does.
    usage=$(fetch_usage "$owner" "$day") || die "could not read billing usage"
    repos=$(fetch_repos "$owner") || die "could not list repos"
    out=$(jq -rn \
        --argjson usage "$usage" --argjson repos "$repos" --arg today "$day" \
        --argjson included "$INCLUDED_MINUTES" --argjson warn "$WARN_PERCENT" \
        --argjson rate "$LINUX_RATE" '
        ([$repos[] | select(.isPrivate) | .name]) as $private
        | ($today | strptime("%Y-%m-%d")) as $t
        | ($t[2]) as $dom
        | ([$t[0], $t[1] + 1, 0, 0, 0, 0, 0, 0] | mktime | gmtime | .[2]) as $days_in_month
        | [$usage.usageItems[]
            | select(.product == "actions" and .unitType == "Minutes")
            | select(.repositoryName as $r | $private | index($r))
            | {repo: .repositoryName, day: .date[0:10], min: (.grossAmount / $rate)}] as $items
        | ([$items[].min] | add // 0) as $used
        | ($dom - 1) as $full_days
        | if $full_days < 1 then
            "used \($used | floor) of \($included) private minutes; too early in the month to project\nstatus: ok"
          else
            ([$items[] | select(.day < $today) | .min] | add // 0) as $done
            | ($done / $full_days) as $per_day
            | ($per_day * $days_in_month) as $proj
            | ($proj * 100 / $included) as $pct
            | [
                "used \($used | floor) of \($included) private minutes"
                    + " (full days: \($full_days), \($per_day | floor)/day)",
                "projected month-end: \($proj | floor) (\($pct | floor)% of included)",
                (if $proj > $included then
                    "projected to run out on day \(($included / $per_day) | ceil) of \($days_in_month)"
                 else empty end),
                "top repos (projected):",
                ($items | map(select(.day < $today)) | group_by(.repo)
                    | map({repo: .[0].repo, p: (([.[].min] | add) / $full_days * $days_in_month)})
                    | sort_by(-.p) | .[:5][] | "  \(.p | floor)\t\(.repo)"),
                "status: \(if $pct >= $warn then "WARN" else "ok" end)"
              ] | join("\n")
          end') || die "could not compute the forecast"
    echo "$out"
    case "$out" in *"status: WARN"*) return 1 ;; esac
}

# One API call per run, 8 at a time: a busy repo's month takes ~20 s. The
# wait is the fetch itself; billing usage has no per-job breakdown to use instead.
fetch_jobs() { # $1 owner/repo, $2 since → [{workflow, job, started_at, completed_at}]
    if [ -n "${GH_ACTIONS_COST_JOBS_JSON:-}" ]; then
        cat "$GH_ACTIONS_COST_JOBS_JSON"
        return
    fi
    gh api --paginate "/repos/$1/actions/runs?created=>=$2&per_page=100" \
        --jq '.workflow_runs[].id' \
        | xargs -P 8 -I{} gh api "/repos/$1/actions/runs/{}/jobs?per_page=100" \
            --jq '.jobs[] | select(.started_at and .completed_at)
                  | {workflow: .workflow_name, job: .name, started_at, completed_at}' \
        | jq -s .
}

breakdown() {
    [ $# -ge 1 ] || usage
    local since=${2:-$(today | cut -c1-8)01}
    fetch_jobs "$1" "$since" | jq -r '
        map(((.completed_at | fromdate) - (.started_at | fromdate)) as $s
            | {key: "\(.workflow) / \(.job)", s: $s,
               billed: ([1, (($s + 59) / 60 | floor)] | max)})
        | group_by(.key)
        | map({key: .[0].key, n: length, s: ([.[].s] | add), billed: ([.[].billed] | add)})
        | sort_by(-.billed)
        | (["billed", "actual", "waste", "jobs", "workflow / job"] | @tsv),
          (.[] | [.billed, (.s / 60 | floor),
                  "\(100 - (.s * 100 / (.billed * 60)) | floor)%", .n, .key] | @tsv)'
}

case "${1:-}" in
    forecast) shift; forecast "$@" ;;
    breakdown) shift; breakdown "$@" ;;
    *) usage ;;
esac
