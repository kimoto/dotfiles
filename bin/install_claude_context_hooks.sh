#!/bin/sh
# Register (default) or remove (--uninstall) the "context is filling up" hook,
# the /clear handoff hooks, and the idle compaction minimum in
# ~/.claude/settings.json.
# Same jq-merge contract as install_claude_idle_hooks.sh:
# unrelated settings survive, reruns are no-ops, and anything unexpected only
# warns — never fails the mkworld bootstrap. rmworld.sh runs --uninstall.
set -eu

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
MODE="${1:-install}"

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

warn() { echo "install_claude_context_hooks: $*" >&2; }

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found; skipping"
  exit 0
fi

case "$MODE" in
  install) ;;
  --uninstall)
    [ -f "$SETTINGS" ] || exit 0 ;;
  *) echo "usage: $0 [--uninstall]" >&2; exit 2 ;;
esac

mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || printf '{}\n' >"$SETTINGS"

if ! jq empty "$SETTINGS" 2>/dev/null; then
  warn "$SETTINGS is invalid JSON; leaving it untouched"
  exit 0
fi
if ! jq -e '(.hooks // {}) | type == "object" and all(.[]; type == "array" and all(.[]; type == "object"))' \
    "$SETTINGS" >/dev/null 2>&1; then
  warn "$SETTINGS has an unexpected .hooks shape; leaving it untouched"
  exit 0
fi

tmp="$(mktemp "$SETTINGS_DIR/.settings.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# Drop every entry that runs these handlers (any command-string version), so
# install below is migration-safe strip-then-add.
# jq variables, not shell ones.
# shellcheck disable=SC2016
STRIP='
  def strip_context:
    if .hooks == null then .
    else .hooks |= (with_entries(
        .value |= map(select(
          ([.hooks[]? | .command? // empty | strings]
           | any(contains("claude_context_check.sh") or contains("claude_handoff.sh"))) | not))
      ) | with_entries(select(.value != [])))
    end;
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

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "context and handoff hooks removed from $SETTINGS"
else
  warn "context and handoff hooks registered in $SETTINGS"
fi
