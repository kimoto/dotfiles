#!/bin/sh
# Register (default) or remove (--uninstall) the "you have been away" hooks in
# ~/.claude/settings.json. Same jq-merge contract as install_claude_tmux_hooks.sh:
# unrelated settings survive, reruns are no-ops, and anything unexpected only
# warns — never fails the mkworld bootstrap. rmworld.sh runs --uninstall.
set -eu

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
MODE="${1:-install}"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
GUARDED='[ ! -x "$HOME/bin/claude_idle_recap.sh" ] || "$HOME/bin/claude_idle_recap.sh"'

warn() { echo "install_claude_idle_hooks: $*" >&2; }

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

# Drop every entry that runs this handler (any command-string version), so
# install below is migration-safe strip-then-add.
STRIP='
  def strip_idle:
    if .hooks == null then .
    else .hooks |= (with_entries(
        .value |= map(select(
          ([.hooks[]? | .command? // empty | strings]
           | any(contains("claude_idle_recap.sh"))) | not))
      ) | with_entries(select(.value != [])))
    end;
'

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

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "idle-recap hooks removed from $SETTINGS"
else
  warn "idle-recap hooks registered in $SETTINGS"
fi
