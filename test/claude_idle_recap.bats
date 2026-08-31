#!/usr/bin/env bats

# Tests for bin/claude_idle_recap.sh and bin/install_claude_idle_hooks.sh: the
# notice that fires on the first prompt after a long absence.
#
# What these pin down is when it stays QUIET. A reminder that fires every turn
# is a reminder nobody reads, and the handler runs on every prompt, so a hang or
# a stray line here is felt on every single turn.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HANDLER="$REPO_ROOT/bin/claude_idle_recap.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_idle_hooks.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  export CLAUDE_IDLE_RECAP_STATE="$TMP/state"
  SETTINGS="$HOME/.claude/settings.json"
  PAYLOAD='{"session_id":"s-1","cwd":"/tmp"}'
}

teardown() {
  rm -rf "$TMP"
}

# Pretend the last assistant turn ended $1 seconds ago.
stamp_ago() {
  mkdir -p "$CLAUDE_IDLE_RECAP_STATE"
  echo $(( $(date +%s) - $1 )) >"$CLAUDE_IDLE_RECAP_STATE/s-1"
}

@test "record writes the stamp for this session" {
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' record"
  [ "$status" -eq 0 ]
  [ -s "$CLAUDE_IDLE_RECAP_STATE/s-1" ]
}

@test "the first turn of a session says nothing (no stamp yet)" {
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a short gap says nothing" {
  stamp_ago 600                                  # 10 minutes
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a gap past the threshold prints one line naming the hours" {
  stamp_ago 11520                                # 3.2 hours
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]   # a single line
  [[ "$output" == *"3.2 時間"* ]]
  [[ "$output" == *"session-resume"* ]]
}

@test "the threshold is configurable" {
  stamp_ago 600
  CLAUDE_IDLE_RECAP_MIN=5 run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [[ "$output" == *"時間ぶり"* ]]
}

# Sessions are separate absences: one being active says nothing about another.
@test "each session has its own stamp" {
  stamp_ago 11520
  run sh -c "printf '%s' '{\"session_id\":\"s-2\"}' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unreadable payload never fails the turn" {
  run sh -c "printf 'not json' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  run sh -c "printf 'not json' | '$HANDLER' record"
  [ "$status" -eq 0 ]
}

@test "a corrupt stamp is ignored rather than printed as garbage" {
  mkdir -p "$CLAUDE_IDLE_RECAP_STATE"
  echo "not-a-number" >"$CLAUDE_IDLE_RECAP_STATE/s-1"
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unknown mode errors instead of silently doing nothing" {
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' bogus"
  [ "$status" -eq 2 ]
}

@test "record sweeps stamps older than two weeks" {
  mkdir -p "$CLAUDE_IDLE_RECAP_STATE"
  touch -t 202501010000 "$CLAUDE_IDLE_RECAP_STATE/ancient"
  run sh -c "printf '%s' '$PAYLOAD' | '$HANDLER' record"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_IDLE_RECAP_STATE/ancient" ]
}

# --- registration ---------------------------------------------------------

@test "installer wires Stop to record and the two arrival events to check" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  jq -e '.hooks.Stop[].hooks[] | select(.command | endswith(" record"))' "$SETTINGS" >/dev/null
  jq -e '.hooks.UserPromptSubmit[].hooks[] | select(.command | endswith(" check"))' "$SETTINGS" >/dev/null
  jq -e '.hooks.SessionStart[].hooks[] | select(.command | endswith(" check"))' "$SETTINGS" >/dev/null
}

@test "the registered command is guarded so a missing script never errors" {
  run "$INSTALLER"
  jq -e '.hooks.Stop[].hooks[] | select(.command | startswith("[ ! -x "))' "$SETTINGS" >/dev/null
}

@test "rerunning changes nothing (no stacked duplicates)" {
  "$INSTALLER"
  first="$(cat "$SETTINGS")"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
  n="$(jq '[.hooks[][] | .hooks[]
     | select(.command | contains("claude_idle_recap.sh"))] | length' "$SETTINGS")"
  [ "$n" -eq 3 ]
}

@test "unrelated settings and other hooks survive" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'JSON'
{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other"}]}]}}
JSON
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = opus ]
  jq -e '.hooks.Stop[].hooks[] | select(.command == "echo other")' "$SETTINGS" >/dev/null
}

@test "--uninstall removes our hooks and keeps everything else" {
  mkdir -p "$HOME/.claude"
  printf '{"model":"opus"}\n' >"$SETTINGS"
  "$INSTALLER"
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  left="$(jq '[.hooks // {} | .[][]? | .hooks[]?
     | select(.command | contains("claude_idle_recap.sh"))] | length' "$SETTINGS")"
  [ "$left" -eq 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = opus ]
}

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf 'not json' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}
