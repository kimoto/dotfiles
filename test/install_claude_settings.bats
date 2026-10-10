#!/usr/bin/env bats

# Tests for bin/install_claude_settings.sh: keep the shared keys of
# ~/.claude/settings.json in step with claudecode/settings-shared.json without
# touching anything that belongs to the machine. The script writes the shared
# file of its OWN repo, so each test runs a copy placed in a throwaway repo,
# against a throwaway $HOME.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/claudecode"
  cp "$REPO_ROOT/bin/install_claude_settings.sh" "$TMP/repo/bin/"
  cp "$REPO_ROOT/claudecode/settings-shared.json" "$TMP/repo/claudecode/"
  SCRIPT="$TMP/repo/bin/install_claude_settings.sh"
  SHARED="$TMP/repo/claudecode/settings-shared.json"
  export HOME="$TMP/home"
  export XDG_STATE_HOME="$TMP/state"
  mkdir -p "$HOME/.claude"
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TMP"
}

# Write $2 (a jq filter) over file $1.
jq_edit() {
  jq "$2" "$1" >"$TMP/edit" && cat "$TMP/edit" >"$1"
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
  fake="$TMP/other/claudecode"
  mkdir -p "$fake"
  printf '{"outputStyle": "Concise"}\n' >"$fake/settings-cloud.json"
  ln -s "$fake/settings-cloud.json" "$SETTINGS"
  run "$SCRIPT" --sync
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
  jq_edit "$SETTINGS" '.theme = "light"'
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  jq -e '. == {"enabledPlugins": {"figma@synced": false}, "theme": "light"}' \
    "$SETTINGS" >/dev/null
}

@test "sync: a key changed here since the last sync lands in the shared file" {
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq_edit "$SETTINGS" '.theme = "light"'
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq -e '.theme == "light"' "$SHARED" >/dev/null
  jq -e '.theme == "light"' "$SETTINGS" >/dev/null
  [[ "$output" == *"commit or discard"* ]]
}

@test "sync: a key only the repo changed is applied here, not reverted" {
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq_edit "$SHARED" '.theme = "dark"'
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq -e '.theme == "dark"' "$SETTINGS" >/dev/null
  jq -e '.theme == "dark"' "$SHARED" >/dev/null
}

@test "sync: with no record of a last sync, this machine's value is kept" {
  printf '{"theme": "light"}\n' >"$SETTINGS"
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq -e '.theme == "light"' "$SHARED" >/dev/null
  jq -e '.theme == "light"' "$SETTINGS" >/dev/null
}

@test "sync: @synced plugins and the machine's own keys never reach the shared file" {
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq_edit "$SETTINGS" \
    '.enabledPlugins["figma@synced"] = true | .enabledPlugins["new@market"] = true | .permissions = {"allow": ["x"]}'
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  jq -e '.enabledPlugins["new@market"] == true' "$SHARED" >/dev/null
  jq -e '.enabledPlugins | has("figma@synced") | not' "$SHARED" >/dev/null
  jq -e 'has("permissions") | not' "$SHARED" >/dev/null
}

@test "sync: a second run with nothing changed writes neither file" {
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  touch -t 200001010000 "$SETTINGS" "$SHARED"
  ref="$TMP/ref"
  touch -t 200101010000 "$ref"
  run "$SCRIPT" --sync
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$SETTINGS" -ot "$ref" ]
  [ "$SHARED" -ot "$ref" ]
}

@test "the shared statusLine prints nothing and exits 0 without claude-hud" {
  cmd="$(jq -r '.statusLine.command' "$SHARED")"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c "$cmd" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
