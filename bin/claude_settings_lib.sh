#!/bin/sh
# The jq-merge contract every bin/install_claude_*.sh shares, so each installer
# only says which hooks it owns: unrelated settings survive, reruns are no-ops,
# and anything unexpected only warns — never fails the mkworld bootstrap.
# This file is *sourced*, not executed, by a POSIX sh script:
#
#   # shellcheck source=bin/claude_settings_lib.sh
#   . "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"
#   settings_open "$@"      # sets MODE and tmp; may exit 0
#   STRIP=$(strip_def strip_x 'contains("x.sh")')
#   jq ... "$SETTINGS" >"$tmp"
#   settings_commit "x hooks"

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"

warn() { echo "$(basename "$0" .sh): $*" >&2; }

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
# every entry whose command passes the test, whatever version of the command
# string an older install wrote. Install strips before it adds, so a rerun or
# an upgrade never leaves two copies.
strip_def() {
  printf '%s\n' "
  def $1:
    if .hooks == null then .
    else .hooks |= (with_entries(
        .value |= map(select(
          ([.hooks[]? | .command? // empty | strings]
           | any($2)) | not))
      ) | with_entries(select(.value != [])))
    end;"
}

# settings_commit <what>: write $tmp over the settings when it differs.
settings_commit() {
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
