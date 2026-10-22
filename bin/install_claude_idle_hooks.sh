#!/bin/sh
# Register (default) or remove (--uninstall) the "you have been away" hooks in
# ~/.claude/settings.json.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
GUARDED='[ ! -x "$HOME/bin/claude_idle_recap.sh" ] || "$HOME/bin/claude_idle_recap.sh"'

settings_open "$@"

STRIP=$(strip_def strip_idle 'contains("claude_idle_recap.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_idle" "$SETTINGS" >"$tmp"
else
  jq --arg cmd "$GUARDED" "$STRIP"'
    def ensure($event; $arg):
      .hooks[$event] = ((.hooks[$event] // [])
        + [{hooks: [{type: "command", command: ($cmd + " " + $arg)}]}]);
    strip_idle
    # ★The stamp is the END of an assistant turn, so a long tool run does not
    #   read as an absence.
    | ensure("Stop";             "record")
    # Nothing fires when someone merely looks at a terminal that stayed open, so
    # the notice rides the first prompt after the gap.
    | ensure("UserPromptSubmit"; "check")
    # Reopening a session (--continue/--resume) is the one real "returned" event.
    | ensure("SessionStart";     "check")
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "idle-recap hooks"
