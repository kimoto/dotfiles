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
  export CLAUDE_CONTEXT_WINDOW=500000
  unset CLAUDE_CONTEXT_WARN_PCT CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
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
  turn 200000                                    # 40%
  check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "crossing 60% tells both the person and the model, naming handoff" {
  turn 310000
  check
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.systemMessage | contains("310k/500k (62%)")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("handoff")' >/dev/null
}

@test "each threshold speaks once per climb" {
  turn 310000
  check
  [ -n "$output" ]
  turn 330000
  check
  [ -z "$output" ]
}

@test "crossing 80% speaks again, with the firmer notice" {
  turn 310000
  check
  turn 420000
  check
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext
    | contains("新しい大きな作業は始めない")' >/dev/null
}

# After compact or /clear the size drops; the next climb must warn again.
@test "a drop below the threshold re-arms it" {
  turn 310000
  check
  turn 50000
  check
  [ -z "$output" ]
  turn 310000
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
  turn 310000
  printf '{"type":"assistant","mess' >>"$TRANSCRIPT"
  check
  [ -n "$output" ]
}

@test "the window falls back to autoCompactWindow in settings.json" {
  unset CLAUDE_CONTEXT_WINDOW
  mkdir -p "$HOME/.claude"
  printf '{"autoCompactWindow": 1000000}\n' >"$SETTINGS"
  turn 310000                                    # 31% of 1M
  check
  [ -z "$output" ]
}

@test "Claude Code's own window variable outranks settings.json" {
  unset CLAUDE_CONTEXT_WINDOW
  mkdir -p "$HOME/.claude"
  printf '{"autoCompactWindow": 1000000}\n' >"$SETTINGS"
  turn 310000                                    # 62% of 500K
  CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
  [ -n "$output" ]
}

@test "the window accepts the setting's 500k / 1M / bare-thousands forms" {
  unset CLAUDE_CONTEXT_WINDOW
  mkdir -p "$HOME/.claude"
  turn 310000
  for w in '"500k"' '500' '"1M"' '"1.5M"'; do
    printf '{"autoCompactWindow": %s}\n' "$w" >"$SETTINGS"
    rm -rf "$CLAUDE_CONTEXT_CHECK_STATE"
    check
    [ "$status" -eq 0 ]
    case "$w" in *1M*) [ -z "$output" ] ;; *) [ -n "$output" ] ;; esac   # 1.5M -> 200K fallback
  done
}

# The cloud environment compacts at 80% of the window: 500K -> 400K.
@test "percentages are of the point where compact fires" {
  turn 250000                                    # 50% of 500K, 62% of 400K
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
  printf '%s' "$output" | jq -e '.systemMessage | contains("250k/400k (62%)")' >/dev/null
}

@test "the thresholds are configurable" {
  turn 100000                                    # 20%
  CLAUDE_CONTEXT_WARN_PCT="10" run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER'"
  [ -n "$output" ]
}

@test "each session keeps its own state" {
  turn 310000
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

@test "rerunning changes nothing (no stacked duplicates)" {
  "$INSTALLER"
  first="$(cat "$SETTINGS")"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
  n="$(jq '[.hooks[][] | .hooks[]
     | select(.command | contains("claude_context_check.sh"))] | length' "$SETTINGS")"
  [ "$n" -eq 1 ]
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
  left="$(jq '[.hooks[][] | .hooks[] | select(.command | contains("claude_context_check.sh"))] | length' "$SETTINGS")"
  [ "$left" -eq 0 ]
}

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf 'not json' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}
