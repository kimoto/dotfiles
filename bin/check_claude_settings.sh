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
# permissions are allowed only in the narrow shapes checked below: the env
# variables named in ENV_ALLOWED, and deny and ask rules. Claude Code has no
# per-machine user settings file, so whatever this file cannot carry is lost on
# a linked machine — a Keychain deny among it.
#
# This gate checks names and shapes, not what a string says: a token written
# into a hook command or a private name in a rule passes it. gitleaks and
# check_private_terms.sh, which run beside it in pre-commit and CI, are what
# read the contents.
# shellcheck disable=SC2016 # "$schema" is a key name, not a shell variable
ALLOWED='[
  "$schema", "advisorModel", "agentPushNotifEnabled", "attribution",
  "autoCompactWindow", "autoMode", "cleanupPeriodDays", "enableWorkflows",
  "enabledPlugins", "env", "extraKnownMarketplaces", "hooks",
  "inputNeededNotifEnabled", "language", "model", "outputStyle", "permissions",
  "remoteControlAtStartup", "skipWorkflowUsageWarning", "statusLine",
  "switchModelsOnFlag", "theme", "voice"
]'

# By name, not by prefix: CLAUDE_CODE_OAUTH_TOKEN is a credential and
# CLAUDE_CODE_SHELL_PREFIX runs before every command, so the prefix alone
# says nothing about what is safe to publish.
ENV_ALLOWED='["CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS"]'

# No mapfile, and the empty-array guard below: macOS still ships bash 3.2.
files=()
if [ "$#" -eq 0 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files 'claudecode/settings*.json')
else
  for f in "$@"; do
    # A file deleted from the tree but still staged is still what gets committed.
    case "$f" in claudecode/settings*.json)
      if [ -f "$f" ] || git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        files+=("$f")
      fi ;;
    esac
  done
fi

failed=0
for f in ${files[@]+"${files[@]}"}; do
  # What is staged is what gets committed: read the index when the file is in
  # it, so a clean working tree cannot vouch for a dirty staged copy.
  # An intent-to-add entry stages nothing yet and an unresolved merge has no
  # single staged copy: read the working tree for those.
  content="$(git show ":$f" 2>/dev/null || true)"
  if [ -z "$content" ] && [ -f "$f" ]; then
    content="$(cat "$f")"
  fi
  problems="$(printf '%s\n' "$content" | jq -r --argjson allowed "$ALLOWED" --argjson env_allowed "$ENV_ALLOWED" '
    if type != "object" then "not a JSON object" else
    [ (keys[] | select(. as $k | $allowed | index($k) | not)
        | "key \"\(.)\" is not on the allow-list"),
      (.env // {} | if type == "object" then
          (keys[] | select(. as $k | $env_allowed | index($k) | not)
            | "env \"\(.)\" is not on the env allow-list")
        else "env is not an object" end),
      # A URL with user:password@ in it carries a credential.
      (.. | strings | select(test("://[^/@ ]+:[^/@ ]*@"))
        | "credential in a URL: \(.[0:40])"),
      # allow widens what a session may do and names paths and commands from
      # wherever it was granted; deny and ask only narrow.
      (.permissions // {} | if type == "object" then
          (keys[] | select(IN("deny", "ask") | not) | "permissions \"\(.)\" is not deny or ask")
        else "permissions is not an object" end),
      # A home directory in a value is this machine leaking; use $HOME.
      # /root/ only at the start of a value or a word, so a URL path is not one.
      (.. | strings | select(test("/(Users|home)/[^/$]|(^|[ \"'\''=])/root/")
          or test("[a-z]:\\\\(users|documents and settings)\\\\"; "i"))
        | "absolute home path: \(.[0:80])"),
      # A local marketplace is a path on this machine, not a source others can fetch.
      (.extraKnownMarketplaces // {} | to_entries[]
        | select(.value.source.source | IN("directory", "file"))
        | "marketplace \"\(.key)\" is a local \(.value.source.source)")
    ] | .[] end')"
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" | sed "s|^|x $f: |" >&2
    failed=1
  else
    echo "ok $f"
  fi
done

exit "$failed"
