#!/usr/bin/env bats

# Tests for bin/install_claude_tmux_hooks.sh: register/unregister the Claude
# Code tmux-indicator hooks in ~/.claude/settings.json without ever touching
# unrelated settings. Each test runs against a throwaway $HOME.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/install_claude_tmux_hooks.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TMP"
}

@test "creates settings.json with every indicator hook on a fresh home" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$SETTINGS" ]
  jq empty "$SETTINGS"
  for ev in Notification Stop UserPromptSubmit PreToolUse PostToolUse SessionStart SessionEnd; do
    jq -e --arg ev "$ev" \
      '.hooks[$ev][].hooks[] | select(.type == "command" and (.command | contains("claude_tmux_indicator.sh")))' \
      "$SETTINGS" >/dev/null
  done
}

@test "wires each event to the right indicator state" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Notification (permission prompt / idle) = attention; Stop = finished.
  jq -e '.hooks.Notification[].hooks[] | select(.command | endswith(" waiting"))' "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop[].hooks[] | select(.command | endswith(" done"))' "$SETTINGS" >/dev/null
  # A new prompt, tool activity, and session start/end all reset it.
  for ev in UserPromptSubmit PreToolUse PostToolUse SessionStart SessionEnd; do
    jq -e --arg ev "$ev" \
      '.hooks[$ev][].hooks[] | select(.command | endswith(" clear"))' "$SETTINGS" >/dev/null
  done
}

@test "registered commands are guarded so a missing script never errors" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  jq -e '.hooks.Stop[].hooks[]
           | select(.command | startswith("[ ! -x ") and contains("claude_tmux_indicator.sh"))' \
    "$SETTINGS" >/dev/null
  cmd="$(jq -r '.hooks.Stop[].hooks[]
                  | select(.command | contains("claude_tmux_indicator.sh")).command' "$SETTINGS")"
  run sh -c "$cmd"   # script does not exist under this fake $HOME
  [ "$status" -eq 0 ]
}

@test "is idempotent: a second run changes nothing" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  first="$(cat "$SETTINGS")"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
}

@test "a no-op rerun does not rewrite the file at all" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  touch -t 200001010000 "$SETTINGS"
  ref="$TMP/ref"
  touch -t 200101010000 "$ref"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Still older than the reference file -> mtime untouched -> not rewritten.
  [ "$SETTINGS" -ot "$ref" ]
}

@test "preserves unrelated settings and pre-existing hooks" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "echo custom-stop"}]}]
  }
}
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = "opus" ]
  jq -e '.hooks.Stop[].hooks[] | select(.command == "echo custom-stop")' "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop[].hooks[] | select(.command | contains("claude_tmux_indicator.sh"))' "$SETTINGS" >/dev/null
}

@test "writes through a symlinked settings.json instead of replacing it" {
  mkdir -p "$HOME/.claude" "$TMP/settings-repo"
  printf '{"model": "opus"}\n' >"$TMP/settings-repo/settings.json"
  ln -s "$TMP/settings-repo/settings.json" "$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -L "$SETTINGS" ]
  jq -e '.hooks.Stop' "$TMP/settings-repo/settings.json" >/dev/null
  [ "$(jq -r '.model' "$TMP/settings-repo/settings.json")" = "opus" ]
}

@test "replaces a stale registration instead of stacking a duplicate" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'EOF'
{"hooks": {"Notification": [{"hooks": [
  {"type": "command", "command": "$HOME/bin/claude_tmux_indicator.sh waiting"}]}]}}
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  count="$(jq '[.hooks.Notification[].hooks[]
                 | select(.command | contains("claude_tmux_indicator.sh"))] | length' "$SETTINGS")"
  [ "$count" -eq 1 ]
}

@test "--uninstall removes every indicator hook and keeps everything else" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "echo custom-stop"}]}]
  }
}
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  run jq -e '.. | .command? // empty | select(contains("claude_tmux_indicator.sh"))' "$SETTINGS"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = "opus" ]
  jq -e '.hooks.Stop[].hooks[] | select(.command == "echo custom-stop")' "$SETTINGS" >/dev/null
}

@test "--uninstall with no settings.json is a silent no-op" {
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$SETTINGS" ]
}

@test "leaves an array-shaped hooks key untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf '{"hooks": []}\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = '{"hooks": []}' ]
  [[ "$output" == *"unexpected"* ]]
}

@test "leaves a non-array event value untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf '{"hooks": {"Stop": "not-an-array"}}\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = '{"hooks": {"Stop": "not-an-array"}}' ]
  [[ "$output" == *"unexpected"* ]]
}

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf '{broken\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = '{broken' ]
  [[ "$output" == *"invalid"* ]]
}
