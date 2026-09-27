#!/bin/sh
# Merge (default) or remove (--uninstall) the keys in claudecode/settings-shared.json
# into ~/.claude/settings.json. Same jq-merge contract as install_claude_idle_hooks.sh:
# unrelated settings survive, reruns are no-ops, and anything unexpected only
# warns — never fails the mkworld bootstrap. rmworld.sh runs --uninstall.
#
# The file itself stays this machine's own (permissions, hooks, anything that
# must not reach a public repo); only the keys listed in the shared file are ours.
set -eu

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SHARED="$BASE_DIR/claudecode/settings-shared.json"
SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
MODE="${1:-install}"

warn() { echo "install_claude_settings: $*" >&2; }

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

# A cloud container links settings.json to claudecode/settings-cloud.json;
# writing through that link would put these keys into the repo.
case "$(readlink -f "$SETTINGS" 2>/dev/null || true)" in
  */claudecode/settings-cloud.json)
    warn "$SETTINGS is the cloud settings link; leaving it untouched"
    exit 0 ;;
esac

mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || printf '{}\n' >"$SETTINGS"

if ! jq empty "$SETTINGS" 2>/dev/null; then
  warn "$SETTINGS is invalid JSON; leaving it untouched"
  exit 0
fi

tmp="$(mktemp "$SETTINGS_DIR/.settings.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# $schema describes the shared file, not this one.
if [ "$MODE" = "--uninstall" ]; then
  # Only what still holds our value: a key changed here since is this machine's.
  jq --slurpfile s "$SHARED" '
    ($s[0] | del(."$schema")) as $shared
    | reduce ($shared | keys[]) as $k (.;
        if ($shared[$k] | type) == "object" and (.[$k] | type) == "object" then
          .[$k] |= with_entries(select(.value != $shared[$k][.key]))
          | if .[$k] == {} then del(.[$k]) else . end
        elif .[$k] == $shared[$k] then del(.[$k])
        else . end)
  ' "$SETTINGS" >"$tmp"
else
  jq --slurpfile s "$SHARED" '. * ($s[0] | del(."$schema"))' "$SETTINGS" >"$tmp"
fi

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# Name every key that moved: shared wins, so a change made here with /config
# is reverted, and it should not be reverted silently.
changed="$(jq -rn --slurpfile a "$SETTINGS" --slurpfile b "$tmp" '
  [($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | join(", ")')"
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "shared keys removed from $SETTINGS: $changed"
else
  warn "shared keys set in $SETTINGS: $changed"
fi
