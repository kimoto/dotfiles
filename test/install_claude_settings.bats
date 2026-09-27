#!/usr/bin/env bats

# Tests for bin/install_claude_settings.sh: merge the shared keys into
# ~/.claude/settings.json without touching anything that belongs to the
# machine. Each test runs against a throwaway $HOME.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/install_claude_settings.sh"
  SHARED="$REPO_ROOT/claudecode/settings-shared.json"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude"
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TMP"
}

@test "sets every shared key on a fresh home, without \$schema" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -e --slurpfile s "$SHARED" \
    '. == ($s[0] | del(."$schema"))' "$SETTINGS" >/dev/null
}

@test "keeps the machine's own keys, hooks and plugins" {
  cat >"$SETTINGS" <<'EOF'
{
  "permissions": {"deny": ["Bash(screencapture:*)"]},
  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "mine"}]}]},
  "enabledPlugins": {"figma@synced": false}
}
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -e '.permissions.deny == ["Bash(screencapture:*)"]' "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop[0].hooks[0].command == "mine"' "$SETTINGS" >/dev/null
  jq -e '.enabledPlugins["figma@synced"] == false' "$SETTINGS" >/dev/null
  jq -e '.enabledPlugins["claude-hud@claude-hud"] == true' "$SETTINGS" >/dev/null
}

@test "names the keys it overwrote" {
  printf '{"theme": "light"}\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *theme* ]]
}

@test "a no-op rerun does not rewrite the file at all" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  touch -t 200001010000 "$SETTINGS"
  ref="$TMP/ref"
  touch -t 200101010000 "$ref"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$SETTINGS" -ot "$ref" ]
}

@test "never writes through the cloud settings link" {
  fake="$TMP/repo/claudecode"
  mkdir -p "$fake"
  printf '{"outputStyle": "Concise"}\n' >"$fake/settings-cloud.json"
  ln -s "$fake/settings-cloud.json" "$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$fake/settings-cloud.json")" = '{"outputStyle": "Concise"}' ]
}

@test "leaves invalid JSON untouched" {
  printf '{not json\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = '{not json' ]
}

@test "uninstall removes only what still holds the shared value" {
  printf '{"enabledPlugins": {"figma@synced": false}}\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq '.theme = "light"' "$SETTINGS" >"$TMP/t" && cat "$TMP/t" >"$SETTINGS"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  jq -e '. == {"enabledPlugins": {"figma@synced": false}, "theme": "light"}' \
    "$SETTINGS" >/dev/null
}

@test "the shared statusLine prints nothing and exits 0 without claude-hud" {
  cmd="$(jq -r '.statusLine.command' "$SHARED")"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c "$cmd" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
