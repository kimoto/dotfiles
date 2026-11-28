#!/bin/sh
# The jq-merge contract every bin/install_claude_*.sh shares, so each installer
# only says which hooks it owns: unrelated settings survive, reruns are no-ops,
# and anything unexpected only warns — never fails the mkworld bootstrap.
# This file is *sourced*, not executed, by a POSIX sh script:
#
#   # shellcheck source=bin/claude_settings_lib.sh
#   . "$(dirname "$(readlink -f "$0" || echo "$0")")/claude_settings_lib.sh"
#   settings_open "$@"      # sets MODE and tmp; may exit 0
#   STRIP=$(strip_def strip_x 'contains("x.sh")')
#   jq ... "$SETTINGS" >"$tmp"
#   settings_commit "x hooks"
#
# The fallback to $0: Git Bash's readlink -f fails (exit 1, no output) for a
# script on a \\wsl.localhost path, where Windows runs these from the WSL checkout.

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"

warn() { echo "$(basename "$0" .sh): $*" >&2; }

# Where the hook commands find the bin/ scripts. Unexpanded by default, so
# $HOME resolves per machine at hook runtime. Windows passes the checkout's
# bin/ instead: its ~/bin is not ours (windows/install_claude_hooks.ps1).
# shellcheck disable=SC2016
HOOK_BIN=${CLAUDE_HOOK_BIN:-'$HOME/bin'}
# It lands between double quotes in every command, unescaped. A failure, not
# a skip: the Windows setup would otherwise end with no hook and no error.
case "${CLAUDE_HOOK_BIN:-}" in
  *'"'* | *'$'* | *'`'* | *\\*)
    echo "$(basename "$0" .sh): CLAUDE_HOOK_BIN holds a quote, \$, \` or \\" >&2
    exit 1 ;;
esac

# guarded <script>: the hook command that runs bin/<script>, behind an -x guard.
# With ~/bin the guard keeps the hook a quiet no-op on a machine without it.
# A CLAUDE_HOOK_BIN names a checkout that should be there, often over
# \\wsl.localhost, so the guard says so and exits 1 instead: Claude Code
# shows that as a hook error, where a quiet no-op would drop the review gate
# and the scans unseen. Arguments appended to the command reach the script.
guarded() {
  if [ -n "${CLAUDE_HOOK_BIN:-}" ]; then
    printf '{ [ -x "%s/%s" ] || { echo "%s/%s is out of reach; hook not run" >&2; exit 1; }; } && "%s/%s"' \
      "$HOOK_BIN" "$1" "$HOOK_BIN" "$1" "$HOOK_BIN" "$1"
  else
    printf '[ ! -x "%s/%s" ] || "%s/%s"' "$HOOK_BIN" "$1" "$HOOK_BIN" "$1"
  fi
}

# settings_open [--uninstall]: check the mode and the file, and leave $tmp
# ready for the new contents. Exits 0, not 1, whenever it backs off.
settings_open() {
  MODE="${1:-install}"

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
}

# strip_def <name> <jq test on a command string>: a jq def <name> that drops
# every hook whose command passes the test, whatever version of the command
# string an older install wrote (settings_commit drops the groups that leaves
# empty); and add_hook($event; $matcher; $hook), which puts a hook in the event's group
# for that matcher ("" for none) so installers that share an event share one
# group. Install strips before it adds, so a rerun never leaves two copies,
# though rerunning one installer alone moves its hooks to the end of a group.
strip_def() {
  printf '%s\n' "
  def $1:
    if .hooks == null then .
    else .hooks |= (map_values(map(
        if (.hooks | type) == \"array\" then
          (.hooks | length) as \$n
          | .hooks |= map(select(
              (.command? // null) as \$c
              | (\$c | type) == \"string\" and (\$c | $2) | not))
          | if .hooks == [] and \$n > 0 then .stripped = true else . end
        else . end)))
    end;
  def add_hook(\$event; \$matcher; \$hook):
    (.hooks[\$event] // []) as \$groups
    | (\$groups | map((.matcher // \"\") == \$matcher) | index(true)) as \$i
    | if \$i == null then
        .hooks[\$event] = \$groups
          + [(if \$matcher == \"\" then {} else {matcher: \$matcher} end)
             + {hooks: [\$hook]}]
      else .hooks[\$event][\$i].hooks += [\$hook] | del(.hooks[\$event][\$i].stripped) end;"
}

# settings_commit <what>: write $tmp over the settings when it differs.
settings_commit() {
  # Drop the groups strip emptied and add_hook did not refill, then their events.
  pruned="$(jq 'if .hooks == null then . else .hooks |= (
      map_values(map(select(.stripped != true))) | with_entries(select(.value != [])))
    end' "$tmp")"
  printf '%s\n' "$pruned" >"$tmp"
  if cmp -s "$tmp" "$SETTINGS"; then
    exit 0
  fi
  # cat, not mv: keeps a symlinked settings.json, its permissions and inode.
  cat "$tmp" >"$SETTINGS"
  if [ "$MODE" = "--uninstall" ]; then
    warn "$1 removed from $SETTINGS"
  else
    warn "$1 registered in $SETTINGS"
  fi
}
