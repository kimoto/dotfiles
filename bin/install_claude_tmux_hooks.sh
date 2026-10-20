#!/bin/sh
# Register (default) or remove (--uninstall) the Claude Code → tmux hooks in
# ~/.claude/settings.json: the agent-state hook (config/tmux-agent-status),
# and the handler that keeps a hunk pane on the repo Claude is in. jq-merge:
# unrelated settings survive, reruns are no-ops, and anything unexpected only
# warns — never fails the mkworld bootstrap. rmworld.sh runs --uninstall.
set -eu

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
MODE="${1:-install}"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
HOOK='"$HOME/.config/tmux-agent-status/scripts/hook.sh"'
GUARDED="[ ! -x $HOOK ] || $HOOK"
# shellcheck disable=SC2016
GUARDED_HUNK='[ ! -x "$HOME/bin/claude_tmux_hunk.sh" ] || "$HOME/bin/claude_tmux_hunk.sh"'

warn() { echo "install_claude_tmux_hooks: $*" >&2; }

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
# Only touch the shape Claude Code documents: hooks = object of arrays of objects.
if ! jq -e '(.hooks // {}) | type == "object" and all(.[]; type == "array" and all(.[]; type == "object"))' \
    "$SETTINGS" >/dev/null 2>&1; then
  warn "$SETTINGS has an unexpected .hooks shape; leaving it untouched"
  exit 0
fi

tmp="$(mktemp "$SETTINGS_DIR/.settings.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# Drop every entry that runs any of these scripts, including the state hook's
# old bin/claude_tmux_indicator.sh, so install below is migration-safe
# strip-then-add.
STRIP='
  def strip_indicator:
    if .hooks == null then .
    else .hooks |= (with_entries(
        .value |= map(select(
          ([.hooks[]? | .command? // empty | strings]
           | any(contains("tmux-agent-status/") or contains("claude_tmux_indicator.sh")
                 or contains("claude_tmux_hunk.sh"))) | not))
      ) | with_entries(select(.value != [])))
    end;
'

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_indicator" "$SETTINGS" >"$tmp"
else
  jq --arg cmd "$GUARDED" --arg hunk "$GUARDED_HUNK" "$STRIP"'
    # hook.sh maps each event to a state; this list only says which events.
    def ensure($event):
      .hooks[$event] = ((.hooks[$event] // [])
        + [{hooks: [{type: "command", command: ($cmd + " " + $event)}]}]);
    strip_indicator
    | ensure("Notification")      # permission prompt / idle -> waiting
    | ensure("Stop")              # finished responding -> done
    | ensure("UserPromptSubmit")
    | ensure("PreToolUse")        # fires before any permission prompt
    | ensure("PostToolUse")       # clears the red an approved prompt left
    | ensure("SessionStart")
    | ensure("SessionEnd")
    # EnterWorktree/ExitWorktree move Claude without firing CwdChanged; a `cd`
    # in Bash fires only CwdChanged. Both are needed to follow every move.
    | .hooks.PostToolUse += [{matcher: "EnterWorktree|ExitWorktree",
                              hooks: [{type: "command", command: $hunk}]}]
    | .hooks.CwdChanged = ((.hooks.CwdChanged // [])
                           + [{hooks: [{type: "command", command: $hunk}]}])
  ' "$SETTINGS" >"$tmp"
fi

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "tmux hooks removed from $SETTINGS"
else
  warn "tmux hooks registered in $SETTINGS"
fi
