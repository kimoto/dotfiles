#!/bin/bash
# Wait for a pull request to settle, for a local Claude Code session that has
# no PR-activity subscription: an agent starts it in the background right after
# `gh pr create` (claude_pr_description_reminder.sh says so) and is woken when
# it exits. One line on stdout says what happened.
#
# Usage: watch_pr.sh <pr number | url | branch>   (gh resolves the repo)
# Exit:  0 merged, 1 a check failed, 2 usage, 3 closed unmerged,
#        4 GitHub kept failing.
set -uo pipefail

if [ $# -ne 1 ]; then
  echo "usage: watch_pr.sh <pr number | url | branch>" >&2
  exit 2
fi
pr=$1

# A PR that just moved (a push, a check finishing) tends to move again soon,
# so it is polled every 30 s; each poll that sees nothing new doubles the wait,
# up to 1 min. A merge is then heard at most a minute late, and a PR left for
# hours of review costs 60 calls an hour, far under GitHub's 5000.
min_interval=30
max_interval=60
# While a check is still running, a failure is heard within 10 s. Not
# `gh pr checks --watch`: it waits for the checks only, so one that never
# finishes would hide a merge or close.
running_interval=10
# Ten failed polls in a row, by then minutes apart, is an outage or a PR that
# is gone, not a blip.
max_failures=10

# A check run reports .conclusion, a legacy commit status .state. Only the
# newest run of each check counts, and CANCELLED is not a failure: every
# workflow here cancels in progress, so a push or a body edit leaves a
# cancelled run in the rollup, alone until its replacement registers.
failing='[.statusCheckRollup // [] | group_by(.name // .context)[] | max_by(.startedAt // "")
  | select((.conclusion // .state // "")
      | IN("FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"))
  | (.name // .context)] | join(", ")'
running='any(.statusCheckRollup[]?;
  (.status // "") != "" and .status != "COMPLETED" or (.state // "") == "PENDING")'

wait_and_back_off() {
  sleep "$interval"
  interval=$((interval * 2))
  [ "$interval" -le "$max_interval" ] || interval=$max_interval
}

interval=$min_interval
previous=""
failures=0
while true; do
  if ! json=$(gh pr view "$pr" --json state,url,statusCheckRollup 2>/dev/null); then
    failures=$((failures + 1))
    if [ "$failures" -ge "$max_failures" ]; then
      echo "giving up: gh pr view $pr failed $failures times in a row"
      exit 4
    fi
    wait_and_back_off
    continue
  fi
  failures=0
  if [ "$json" != "$previous" ]; then
    interval=$min_interval
    previous=$json
  fi
  url=$(jq -r '.url' <<<"$json")
  case $(jq -r '.state' <<<"$json") in
    MERGED) echo "merged: $url"; exit 0 ;;
    CLOSED) echo "closed without merging: $url"; exit 3 ;;
  esac
  failed=$(jq -r "$failing" <<<"$json")
  if [ -n "$failed" ]; then
    echo "check failed ($failed): $url"
    exit 1
  fi
  if jq -e "$running" <<<"$json" >/dev/null; then
    sleep "$running_interval"
  else
    wait_and_back_off
  fi
done
