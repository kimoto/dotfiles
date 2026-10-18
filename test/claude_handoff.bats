#!/usr/bin/env bats

# Tests for bin/claude_handoff.sh: the handoff carried across /clear.
#
# What these pin down is that only /clear carries anything. A new `claude` in
# the same directory is new work, and handing it a stale handoff would steer it
# toward a task nobody asked for.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  H="$REPO_ROOT/bin/claude_handoff.sh"
  TMP="$(mktemp -d)"
  export CLAUDE_HANDOFF_STATE="$TMP/state"
  WORK="$TMP/work"
  mkdir -p "$WORK"
}

teardown() {
  rm -rf "$TMP"
}

save() { (cd "$WORK" && printf '%s' "$1" | "$H" save); }
end_() { printf '{"cwd":"%s","transcript_path":"/t/old.jsonl","reason":"%s"}' "$WORK" "$1" | "$H" end; }
start() { run sh -c "printf '{\"cwd\":\"%s\",\"source\":\"%s\"}' '$WORK' '$1' | '$H' start"; }

@test "/clear hands the saved prompt and the old transcript to the new session" {
  save "目的: X を直す"
  end_ clear
  start clear
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("目的: X を直す")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("/t/old.jsonl")' >/dev/null
}

@test "it is handed over once" {
  save "目的: X"
  end_ clear
  start clear
  start clear
  [ -z "$output" ]
}

@test "/clear without a saved prompt stays a plain reset" {
  end_ clear
  [ -z "$(ls -A "$CLAUDE_HANDOFF_STATE" 2>/dev/null)" ]
  start clear
  [ -z "$output" ]
}

@test "a fresh start in the same directory inherits nothing" {
  save "目的: X"
  start startup
  [ -z "$output" ]
  end_ prompt_input_exit
  start clear
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("/t/old.jsonl") | not' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("目的: X")' >/dev/null
}

@test "another directory's handoff is not handed over" {
  save "目的: X"
  WORK="$TMP/other"
  mkdir -p "$WORK"
  end_ clear
  start clear
  [ -z "$output" ]
}

@test "a handoff older than a day is dropped" {
  save "目的: X"
  touch -t 202501010000 "$CLAUDE_HANDOFF_STATE"/*.md
  start clear
  [ -z "$output" ]
}

@test "the saved prompt is private to the user" {
  save "目的: X"
  [ "$(stat -c %a "$CLAUDE_HANDOFF_STATE"/*.md 2>/dev/null || stat -f %Lp "$CLAUDE_HANDOFF_STATE"/*.md)" = 600 ]
}

@test "an empty save fails instead of parking nothing" {
  run sh -c "cd '$WORK' && printf '' | '$H' save"
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$CLAUDE_HANDOFF_STATE")" ]
}

@test "an unreadable payload never fails the session" {
  run sh -c "printf 'not json' | '$H' start"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run sh -c "printf 'not json' | '$H' end"
  [ "$status" -eq 0 ]
}
