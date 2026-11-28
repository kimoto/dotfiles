#!/bin/sh
# Register (default) or remove (--uninstall) the after-push PR description
# reminder in ~/.claude/settings.json, so it fires in every repo, not only here.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0" || echo "$0")")/claude_settings_lib.sh"

GUARDED=$(guarded claude_pr_description_reminder.sh)

settings_open "$@"

STRIP=$(strip_def strip_pr 'contains("claude_pr_description_reminder.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_pr" "$SETTINGS" >"$tmp"
else
  jq --arg cmd "$GUARDED" "$STRIP"'
    strip_pr
    | .hooks.PostToolUse = ((.hooks.PostToolUse // [])
        + [{matcher: "Bash|PowerShell", hooks: [{type: "command", command: $cmd}]}])
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "PR description hook"
