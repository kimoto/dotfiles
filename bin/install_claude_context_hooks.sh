#!/bin/sh
# Register (default) or remove (--uninstall) the "context is filling up" hook,
# the /clear handoff hooks, and the idle compaction minimum in
# ~/.claude/settings.json.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
GUARDED='[ ! -x "$HOME/bin/claude_context_check.sh" ] || "$HOME/bin/claude_context_check.sh"'
# shellcheck disable=SC2016
HANDOFF='[ ! -x "$HOME/bin/claude_handoff.sh" ] || "$HOME/bin/claude_handoff.sh"'

# ★Idle compaction summarizes a conversation left ~54 minutes, before its 1h
# prompt cache expires; past that, the next prompt pays to cache it all again.
# Its stock 200K minimum would summarize work the handoff notice has not yet
# flagged, so it starts at that notice's first threshold (WARN_TOKENS in
# claude_context_check.sh; a test keeps the two equal).
IDLE_MIN=400000

settings_open "$@"

# jq variables, not shell ones.
# shellcheck disable=SC2016
STRIP="$(strip_def strip_context 'contains("claude_context_check.sh") or contains("claude_handoff.sh")')"'
  # Only the value install writes: a hand-set minimum is not ours.
  def strip_idle_compaction:
    if .env.CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS == $idle_min
    then del(.env.CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS)
      | if .env == {} then del(.env) else . end
    else . end;
'

if [ "$MODE" = "--uninstall" ]; then
  jq --arg idle_min "$IDLE_MIN" "$STRIP strip_context | strip_idle_compaction" "$SETTINGS" >"$tmp"
else
  jq --arg cmd "$GUARDED" --arg handoff "$HANDOFF" --arg idle_min "$IDLE_MIN" "$STRIP"'
    def ensure($event; $c):
      .hooks[$event] = ((.hooks[$event] // [])
        + [{hooks: [{type: "command", command: $c}]}]);
    strip_context
    # An earlier install wrote false; idle compaction stays on now.
    | if .idleCompaction == false then del(.idleCompaction) else . end
    | if .env.CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS then .
      else .env.CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS = $idle_min end
    # UserPromptSubmit, not Stop: its output reaches both the person
    # (systemMessage) and the model (additionalContext) before the turn starts.
    | ensure("UserPromptSubmit"; $cmd)
    # /clear fires SessionEnd (reason "clear") on the old session, then
    # SessionStart (source "clear") on the new one, both with the same cwd.
    | ensure("SessionEnd";   $handoff + " end")
    | ensure("SessionStart"; $handoff + " start")
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "context and handoff hooks"
