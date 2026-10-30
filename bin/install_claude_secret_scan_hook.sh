#!/bin/sh
# Register (default) or remove (--uninstall) the gitleaks scan before a commit
# the model runs (claude_commit_secret_scan.sh) in ~/.claude/settings.json.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
COMMIT_SCAN='[ ! -x "$HOME/bin/claude_commit_secret_scan.sh" ] || "$HOME/bin/claude_commit_secret_scan.sh"'

settings_open "$@"

STRIP=$(strip_def strip_security 'contains("claude_commit_secret_scan.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_security" "$SETTINGS" >"$tmp"
else
  jq --arg commit "$COMMIT_SCAN" "$STRIP"'
    def ensure($event; $matcher; $c; $timeout):
      .hooks[$event] += [{matcher: $matcher, hooks: [{type: "command", command: $c, timeout: $timeout}]}];
    strip_security
    # gitleaks reads the whole diff; 30s covers a large one without letting a
    # hung scan hold the session.
    | ensure("PreToolUse"; "Bash"; $commit; 30)
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "secret scan hook"
