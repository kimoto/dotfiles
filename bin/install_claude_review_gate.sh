#!/bin/sh
# Register (default) or remove (--uninstall) the review gate
# (claude_review_gate.sh) in ~/.claude/settings.json: before a push and before
# a PR is created. How the merge stays safe: bin/claude_settings_lib.sh.
# rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
GATE='[ ! -x "$HOME/bin/claude_review_gate.sh" ] || "$HOME/bin/claude_review_gate.sh"'

settings_open "$@"

STRIP=$(strip_def strip_gate 'contains("claude_review_gate.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_gate" "$SETTINGS" >"$tmp"
else
  jq --arg gate "$GATE" "$STRIP"'
    def ensure($event; $matcher; $c):
      .hooks[$event] += [{matcher: $matcher, hooks: [{type: "command", command: $c, timeout: 10}]}];
    strip_gate
    | ensure("PreToolUse"; "Bash|mcp__.*__create_pull_request"; $gate)
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "review gate hook"
