#!/bin/sh
# Keep the keys in claudecode/settings-shared.json in step with
# ~/.claude/settings.json. Same jq-merge contract as install_claude_idle_hooks.sh:
# unrelated settings survive, reruns are no-ops, and anything unexpected only
# warns — never fails the mkworld bootstrap.
#
#   (default)    shared file -> settings.json
#   --sync       both ways, per key: a key this machine changed since the last
#                sync is copied into the shared file (so it shows up as a diff
#                in this repo), a key only the repo changed is applied here
#   --uninstall  remove the keys that still hold the shared value
#
# The file itself stays this machine's own (permissions, hooks, anything that
# must not reach a public repo); only the keys listed in the shared file are ours.
set -eu

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SHARED="$BASE_DIR/claudecode/settings-shared.json"
SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
# What the last sync left both sides agreeing on. Without it a value pulled from
# another machine and a value changed here look the same: they just differ.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STATE="$STATE_DIR/claude-settings-synced.json"
MODE="${1:-install}"

warn() { echo "install_claude_settings: $*" >&2; }

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found; skipping"
  exit 0
fi

case "$MODE" in
  install|--sync) ;;
  --uninstall)
    [ -f "$SETTINGS" ] || exit 0 ;;
  *) echo "usage: $0 [--sync|--uninstall]" >&2; exit 2 ;;
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
shared_tmp="$(mktemp "$SETTINGS_DIR/.settings-shared.json.XXXXXX")"
trap 'rm -f "$tmp" "$shared_tmp"' EXIT
cp "$SHARED" "$shared_tmp"

state='null'
[ "$MODE" = "--sync" ] && [ -f "$STATE" ] && state="$(cat "$STATE")"

# claude.ai sync owns the @synced plugins, separately on every machine, so they
# never count as a difference and never reach the shared file.
# shellcheck disable=SC2016 # jq's $k, not the shell's
OURS='
  def ours($k): if $k == "enabledPlugins" and type == "object"
    then with_entries(select(.key | endswith("@synced") | not)) else . end;
'

case "$MODE" in
  --uninstall)
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
    ;;
  install)
    jq --slurpfile s "$SHARED" '. * ($s[0] | del(."$schema"))' "$SETTINGS" >"$tmp"
    ;;
  --sync)
    # $schema describes the shared file, not this one.
    jq --slurpfile s "$SHARED" --argjson t "$state" "$OURS"'
      . as $local
      | reduce ($s[0] | del(."$schema") | keys[]) as $k ($s[0];
          ($local[$k] | ours($k)) as $mine
          | if ($local | has($k)) and $mine != .[$k]
               and $mine != $t[$k]
            then .[$k] = $mine else . end)
    ' "$SETTINGS" >"$shared_tmp"
    jq --slurpfile s "$shared_tmp" '. * ($s[0] | del(."$schema"))' "$SETTINGS" >"$tmp"
    ;;
esac

if ! cmp -s "$shared_tmp" "$SHARED"; then
  cat "$shared_tmp" >"$SHARED"
  warn "copied this machine's values into $SHARED; commit or discard them there"
fi

if [ "$MODE" = "--uninstall" ]; then
  rm -f "$STATE"
else
  mkdir -p "$STATE_DIR"
  jq 'del(."$schema")' "$SHARED" >"$STATE"
fi

if cmp -s "$tmp" "$SETTINGS"; then
  exit 0
fi
# Name every key that moved: a change made here that was never synced is
# overwritten by install, and it should not be overwritten silently.
changed="$(jq -rn --slurpfile a "$SETTINGS" --slurpfile b "$tmp" '
  [($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | join(", ")')"
# cat, not mv: keeps a symlinked settings.json, its permissions and inode.
cat "$tmp" >"$SETTINGS"
if [ "$MODE" = "--uninstall" ]; then
  warn "shared keys removed from $SETTINGS: $changed"
else
  warn "shared keys set in $SETTINGS: $changed"
fi
