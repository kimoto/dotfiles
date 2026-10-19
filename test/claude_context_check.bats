#!/usr/bin/env bats

# Tests for bin/claude_context_check.sh and bin/install_claude_context_hooks.sh:
# the notice that the context is filling up and it is time to hand off.
#
# What these pin down is when it stays QUIET. The handler runs on every prompt,
# so a notice that repeats, or a stray line, is felt on every single turn.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HANDLER="$REPO_ROOT/bin/claude_context_check.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_context_hooks.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  export CLAUDE_CONTEXT_CHECK_STATE="$TMP/state"
  unset CLAUDE_CONTEXT_WARN_TOKENS CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  SETTINGS="$HOME/.claude/settings.json"
  TRANSCRIPT="$TMP/t.jsonl"
  : >"$TRANSCRIPT"
  PAYLOAD="{\"session_id\":\"s-1\",\"transcript_path\":\"$TRANSCRIPT\"}"
}

teardown() {
  rm -rf "$TMP"
}

# Append a main-chain assistant turn whose input totals $1 tokens.
turn() {
  printf '%s"cache_read_input_tokens":%d%s\n' \
    '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":1,' \
    "$(( $1 - 1 ))" ',"cache_creation_input_tokens":0,"output_tokens":5}}}' >>"$TRANSCRIPT"
}

check() {
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
}

@test "below the first threshold says nothing" {
  turn 150000
  check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "crossing 200K tells both the person and the model, naming handoff" {
  turn 210000
  check
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.systemMessage | contains("210k")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("handoff")' >/dev/null
}

@test "each threshold speaks once per climb" {
  turn 210000
  check
  [ -n "$output" ]
  turn 230000
  check
  [ -z "$output" ]
}

@test "crossing 300K speaks again, with the firmer notice" {
  turn 210000
  check
  turn 310000
  check
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext
    | contains("新しい大きな作業は始めない")' >/dev/null
}

# After compact or /clear the size drops; the next climb must warn again.
@test "a drop below the threshold re-arms it" {
  turn 210000
  check
  turn 50000
  check
  [ -z "$output" ]
  turn 210000
  check
  [ -n "$output" ]
}

@test "sidechain (subagent) turns are not the session's context" {
  turn 100000
  printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":450000}}}\n' >>"$TRANSCRIPT"
  check
  [ -z "$output" ]
}

@test "a half-written last line does not hide the turn before it" {
  turn 210000
  printf '{"type":"assistant","mess' >>"$TRANSCRIPT"
  check
  [ -n "$output" ]
}

# Compact is only the backstop: wherever it sits, the notice stays put.
@test "the compact window does not move the thresholds" {
  mkdir -p "$HOME/.claude"
  printf '{"autoCompactWindow": 1000000}\n' >"$SETTINGS"
  turn 210000
  CLAUDE_CODE_AUTO_COMPACT_WINDOW=900000 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 \
    run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
  [ -n "$output" ]
}

@test "the thresholds are configurable" {
  turn 120000
  CLAUDE_CONTEXT_WARN_TOKENS="100000" run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
  [ -n "$output" ]
}

@test "each session keeps its own state" {
  turn 210000
  check
  run sh -c "printf '%s' '{\"session_id\":\"s-2\",\"transcript_path\":\"$TRANSCRIPT\"}' | '$HANDLER'"
  [ -n "$output" ]
}

@test "an unreadable payload or missing transcript never fails the turn" {
  run sh -c "printf 'not json' | '$HANDLER'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run sh -c "printf '%s' '{\"session_id\":\"s-1\",\"transcript_path\":\"/nonexistent\"}' | '$HANDLER'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- registration ---------------------------------------------------------

@test "installer wires UserPromptSubmit, guarded against a missing script" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  jq -e '.hooks.UserPromptSubmit[].hooks[]
    | select(.command | startswith("[ ! -x ") and contains("claude_context_check.sh"))' "$SETTINGS" >/dev/null
}

@test "installer wires /clear's SessionEnd and SessionStart to the handoff carrier" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  jq -e '.hooks.SessionEnd[].hooks[] | select(.command | endswith("claude_handoff.sh\" end"))' "$SETTINGS" >/dev/null
  jq -e '.hooks.SessionStart[].hooks[]
    | select(.command | endswith("claude_handoff.sh\" start"))' "$SETTINGS" >/dev/null
}

@test "installer turns idle compaction off, unless someone set it by hand" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.idleCompaction' "$SETTINGS")" = false ]

  printf '{"idleCompaction": true}\n' >"$SETTINGS"
  run "$INSTALLER"
  [ "$(jq -r '.idleCompaction' "$SETTINGS")" = true ]
}

@test "--uninstall takes back idle compaction only when it is ours" {
  "$INSTALLER"
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  [ "$(jq 'has("idleCompaction")' "$SETTINGS")" = false ]

  printf '{"idleCompaction": true}\n' >"$SETTINGS"
  run "$INSTALLER" --uninstall
  [ "$(jq -r '.idleCompaction' "$SETTINGS")" = true ]
}

@test "rerunning changes nothing (no stacked duplicates)" {
  "$INSTALLER"
  first="$(cat "$SETTINGS")"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
  n="$(jq '[.hooks[][] | .hooks[]
     | select(.command | contains("claude_context_check.sh") or contains("claude_handoff.sh"))] | length' "$SETTINGS")"
  [ "$n" -eq 3 ]
}

@test "--uninstall removes our hook and keeps other hooks" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'JSON'
{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo other"}]}]}}
JSON
  "$INSTALLER"
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = opus ]
  jq -e '.hooks.UserPromptSubmit[].hooks[] | select(.command == "echo other")' "$SETTINGS" >/dev/null
  left="$(jq '[.hooks[][] | .hooks[]
     | select(.command | contains("claude_context_check.sh") or contains("claude_handoff.sh"))] | length' "$SETTINGS")"
  [ "$left" -eq 0 ]
}

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf 'not json' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}
