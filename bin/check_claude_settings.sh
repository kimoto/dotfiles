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
# it is added here on purpose — notably apiKeyHelper (a credential). env and
# permissions are allowed only in the narrow shapes checked below: Claude
# Code's own CLAUDE_CODE_* tunables, and deny and ask rules. Claude Code has no
# per-machine user settings file, so whatever this file cannot carry is lost on
# a linked machine — a Keychain deny among it.
# shellcheck disable=SC2016 # "$schema" is a key name, not a shell variable
ALLOWED='[
  "$schema", "advisorModel", "agentPushNotifEnabled", "attribution",
  "autoCompactWindow", "autoMode", "cleanupPeriodDays", "enableWorkflows",
  "enabledPlugins", "env", "extraKnownMarketplaces", "hooks",
  "inputNeededNotifEnabled", "language", "model", "outputStyle", "permissions",
  "remoteControlAtStartup", "skipWorkflowUsageWarning", "statusLine",
  "switchModelsOnFlag", "theme", "voice"
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
      # Any other variable can be a token; the CLAUDE_CODE_ ones are tunables.
      (.env // {} | keys[] | select(startswith("CLAUDE_CODE_") | not)
        | "env \"\(.)\" is not a CLAUDE_CODE_ variable"),
      # allow widens what a session may do and names paths and commands from
      # wherever it was granted; deny and ask only narrow.
      (.permissions // {} | keys[] | select(IN("deny", "ask") | not)
        | "permissions \"\(.)\" is not deny or ask"),
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
