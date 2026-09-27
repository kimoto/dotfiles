#!/bin/bash
# Refuse a Claude Code settings file that would publish something it should not.
# ~/.claude/settings.json is a link into this public repo, so whatever Claude
# Code writes there (/config, "always allow", a plugin install) lands in the
# working tree; this is the check between that and a commit. Shared by CI and
# the lefthook pre-commit hook. Pass files as arguments; with none, every
# tracked claudecode/settings*.json is checked.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
cd "$BASE_DIR"

# Top-level keys a public file may carry. Anything else stops the commit until
# it is added here on purpose — notably env and apiKeyHelper (credentials) and
# permissions (allow rules name paths and commands from wherever they were
# granted).
ALLOWED='[
  "$schema", "advisorModel", "agentPushNotifEnabled", "autoCompactWindow",
  "autoMode", "cleanupPeriodDays", "enableWorkflows", "enabledPlugins",
  "extraKnownMarketplaces", "hooks", "inputNeededNotifEnabled", "language",
  "outputStyle", "remoteControlAtStartup", "skipWorkflowUsageWarning",
  "statusLine", "switchModelsOnFlag", "theme", "voice"
]'

# No mapfile, and the empty-array guard below: macOS still ships bash 3.2.
files=()
if [ "$#" -eq 0 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files 'claudecode/settings*.json')
else
  for f in "$@"; do
    case "$f" in claudecode/settings*.json) [ -f "$f" ] && files+=("$f") ;; esac
  done
fi

failed=0
for f in ${files[@]+"${files[@]}"}; do
  problems="$(jq -r --argjson allowed "$ALLOWED" '
    [ (keys[] | select(. as $k | $allowed | index($k) | not)
        | "key \"\(.)\" is not on the allow-list"),
      # A home directory in a value is this machine leaking; use $HOME.
      (.. | strings | select(test("/(Users|home)/[^/$]"))
        | "absolute home path: \(.[0:80])"),
      # A local marketplace is a path on this machine, not a source others can fetch.
      (.extraKnownMarketplaces // {} | to_entries[]
        | select(.value.source.source | IN("directory", "file"))
        | "marketplace \"\(.key)\" is a local \(.value.source.source)")
    ] | .[]' "$f")"
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" | sed "s|^|x $f: |" >&2
    failed=1
  else
    echo "ok $f"
  fi
done

exit "$failed"
