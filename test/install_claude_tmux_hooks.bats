#!/usr/bin/env bats

# Tests for bin/install_claude_tmux_hooks.sh, the installer that registers the
# claude_tmux_indicator.sh hooks (pane/window color for Claude Code states) in
# ~/.claude/settings.json. The installer must be idempotent and must never
# clobber unrelated user settings — it jq-merges into whatever is already
# there. Each test runs against a throwaway $HOME.

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
  for ev in Notification Stop UserPromptSubmit PreToolUse SessionStart SessionEnd; do
    jq -e --arg ev "$ev" \
      '.hooks[$ev][].hooks[] | select(.type == "command" and (.command | contains("claude_tmux_indicator.sh")))' \
      "$SETTINGS" >/dev/null
  done
}

@test "wires each event to the right indicator state" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Notification (permission prompt / idle) = attention; Stop = finished.
  jq -e '.hooks.Notification[].hooks[] | select(.command | endswith("claude_tmux_indicator.sh waiting"))' \
    "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop[].hooks[] | select(.command | endswith("claude_tmux_indicator.sh done"))' \
    "$SETTINGS" >/dev/null
  # A new prompt, a resumed tool call, and session start/end all reset it.
  for ev in UserPromptSubmit PreToolUse SessionStart SessionEnd; do
    jq -e --arg ev "$ev" \
      '.hooks[$ev][].hooks[] | select(.command | endswith("claude_tmux_indicator.sh clear"))' \
      "$SETTINGS" >/dev/null
  done
}

@test "is idempotent: a second run changes nothing" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  first="$(cat "$SETTINGS")"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
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

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf '{broken\n' >"$SETTINGS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = '{broken' ]
  [[ "$output" == *"invalid"* ]]
}
