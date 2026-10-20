#!/bin/sh
# The one hook command Claude Code and Codex both register, for every event:
#   hook.sh <hook event name>
# Which event means which state is decided here, not in either agent's hook
# config, so the two agents cannot drift apart.
# Always exits 0 and prints nothing but Stop's "{}": exit 2 would block the
# agent, Claude adds UserPromptSubmit's stdout to the conversation, and Codex
# rejects a Stop hook whose stdout is not JSON.
case "${1:-}" in
  # Claude: a permission prompt or the idle reminder. Codex: an approval prompt.
  Notification|PermissionRequest) state=waiting ;;
  Stop) printf '{}\n'; state='done' ;;
  *) state=clear ;;
esac
"$(dirname "$0")/state.sh" "$state" >/dev/null 2>&1 || true
exit 0
