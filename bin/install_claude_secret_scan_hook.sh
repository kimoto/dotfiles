#!/bin/sh
# Register (default) or remove (--uninstall) the gitleaks scan before a commit
# the model runs (claude_commit_secret_scan.sh) in ~/.claude/settings.json.
# Same jq-merge contract as install_claude_idle_hooks.sh: unrelated settings
# survive, reruns are no-ops, and anything unexpected only warns — never fails
# the mkworld bootstrap.
# rmworld.sh runs --uninstall.
set -eu

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
MODE="${1:-install}"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
COMMIT_SCAN='[ ! -x "$HOME/bin/claude_commit_secret_scan.sh" ] || "$HOME/bin/claude_commit_secret_scan.sh"'

warn() { echo "install_claude_secret_scan_hook: $*" >&2; }

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
STRIP='
  def strip_security:
    if .hooks == null then .
    else .hooks |= (with_entries(
        .value |= map(select(
          ([.hooks[]? | .command? // empty | strings]
           | any(contains("claude_commit_secret_scan.sh"))) | not))
      ) | with_entries(select(.value != [])))
    end;
'

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_security" "$SETTINGS" >"$tmp"
else
  jq --arg commit "$COMMIT_SCAN" "$STRIP"'
    def ensure($event; $matcher; $c; $timeout):
      .hooks[$event] = ((.hooks[$event] // [])
        + [{matcher: $matcher, hooks: [{type: "command", command: $c, timeout: $timeout}]}]);
    strip_security
    # gitleaks reads the whole diff; 30s covers a large one without letting a
    # hung scan hold the session.
    | ensure("PreToolUse"; "Bash"; $commit; 30)
  ' "$SETTINGS" >"$tmp"
fi

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "secret scan hook removed from $SETTINGS"
else
  warn "secret scan hook registered in $SETTINGS"
fi
