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

# A merge waits on a person, so a minute apart is soon enough and stays far
# below GitHub's rate limit.
interval=${WATCH_PR_INTERVAL:-60}
# Ten minutes of failed polls is an outage or a PR that is gone, not a blip.
max_failures=10

# A check run reports .conclusion, a legacy commit status .state.
failing='[.statusCheckRollup[]?
  | select((.conclusion // .state // "")
      | IN("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED"))
  | (.name // .context)] | join(", ")'

failures=0
while true; do
  if ! json=$(gh pr view "$pr" --json state,url,statusCheckRollup 2>/dev/null); then
    failures=$((failures + 1))
    if [ "$failures" -ge "$max_failures" ]; then
      echo "giving up: gh pr view $pr failed $failures times in a row"
      exit 4
    fi
    sleep "$interval"
    continue
  fi
  failures=0
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
  sleep "$interval"
done
