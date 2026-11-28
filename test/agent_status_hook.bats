#!/usr/bin/env bats

# config/tmux-agent-status/scripts/hook.sh: the event -> state map both
# agents share, and the output/exit rules that keep it from ever steering the
# agent. A stub state.sh beside a copy of hook.sh records the state it gets.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  cp "$REPO_ROOT/config/tmux-agent-status/scripts/hook.sh" "$TMP/hook.sh"
  printf '#!/bin/sh\necho "$1" >"%s/state"\n' "$TMP" >"$TMP/state.sh"
  chmod +x "$TMP/state.sh"
}

teardown() {
  rm -rf "$TMP"
}

state_for() { # <event>: run the hook, print the state it asked for
  "$TMP/hook.sh" "$1" >/dev/null
  cat "$TMP/state"
}

@test "a prompt waiting on the user is red, from either agent" {
  [ "$(state_for Notification)" = waiting ]       # Claude Code
  [ "$(state_for PermissionRequest)" = waiting ]  # Codex
}

@test "Stop is done and prints the JSON Codex requires" {
  run "$TMP/hook.sh" Stop
  [ "$status" -eq 0 ]
  [ "$output" = '{}' ]
  [ "$(cat "$TMP/state")" = done ]
}

@test "every other event clears silently: Claude adds UserPromptSubmit's stdout to the chat" {
  for ev in UserPromptSubmit PreToolUse PostToolUse SessionStart SessionEnd; do
    run "$TMP/hook.sh" "$ev"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$TMP/state")" = clear ]
  done
}

@test "exits 0 even when state.sh fails: exit 2 would block the agent" {
  printf '#!/bin/sh\nexit 2\n' >"$TMP/state.sh"
  run "$TMP/hook.sh" Notification
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
