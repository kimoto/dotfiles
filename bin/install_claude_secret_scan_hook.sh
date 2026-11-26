#!/bin/sh
# Register (default) or remove (--uninstall) the gitleaks scan before a commit
# the model runs (claude_commit_secret_scan.sh), and the privacy review of
# what it publishes to a public repo (claude_public_privacy_check.sh), in
# ~/.claude/settings.json.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
COMMIT_SCAN='[ ! -x "$HOME/bin/claude_commit_secret_scan.sh" ] || "$HOME/bin/claude_commit_secret_scan.sh"'
# shellcheck disable=SC2016
PRIVACY_CHECK='[ ! -x "$HOME/bin/claude_public_privacy_check.sh" ] || "$HOME/bin/claude_public_privacy_check.sh"'

settings_open "$@"

STRIP=$(strip_def strip_security \
  'contains("claude_commit_secret_scan.sh") or contains("claude_public_privacy_check.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_security" "$SETTINGS" >"$tmp"
else
  jq --arg commit "$COMMIT_SCAN" --arg privacy "$PRIVACY_CHECK" "$STRIP"'
    def ensure($event; $matcher; $c; $timeout):
      .hooks[$event] = ((.hooks[$event] // [])
        + [{matcher: $matcher, hooks: [{type: "command", command: $c, timeout: $timeout}]}]);
    strip_security
    # gitleaks reads the whole diff; 30s covers a large one without letting a
    # hung scan hold the session.
    | ensure("PreToolUse"; "Bash"; $commit; 30)
    # A GitHub MCP write carries its PR or issue text in the call itself. 60s:
    # the review asks a model, which itself stops at 45.
    | ensure("PreToolUse"; "Bash|mcp__.*github.*"; $privacy; 60)
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "secret scan hook"
