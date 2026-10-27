#!/usr/bin/env bats

# Tests for bin/watch_pr.sh. A stub `gh` answers `gh pr view` from a queue of
# canned JSON files, one per poll, so each test plays out a PR's life without
# touching GitHub.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/watch_pr.sh"
  TMP="$(mktemp -d)"
  QUEUE="$TMP/queue"
  mkdir -p "$QUEUE" "$TMP/stubbin"
  export QUEUE
  # Each poll consumes the lowest-numbered file; an empty queue repeats the
  # last answer. A file holding "ERR" makes gh fail that poll.
  cat >"$TMP/stubbin/gh" <<'STUBEOF'
#!/bin/bash
next=$(ls "$QUEUE" | grep -E '^[0-9]+$' | sort -n | head -1)
if [ -n "$next" ]; then
  mv "$QUEUE/$next" "$QUEUE/last"
fi
if [ "$(cat "$QUEUE/last")" = ERR ]; then
  echo "gh: network error" >&2
  exit 1
fi
cat "$QUEUE/last"
STUBEOF
  # A stub sleep returns at once and logs how long the watcher asked to wait.
  SLEEPS="$TMP/sleeps"
  export SLEEPS
  cat >"$TMP/stubbin/sleep" <<'STUBEOF'
#!/bin/bash
echo "$1" >>"$SLEEPS"
STUBEOF
  chmod +x "$TMP/stubbin/gh" "$TMP/stubbin/sleep"
  PATH="$TMP/stubbin:$PATH"
}

waits() {
  tr '\n' ' ' <"$SLEEPS" | sed 's/ $//'
}

teardown() {
  rm -rf "$TMP"
}

# answer N STATE [CHECK_JSON...]: what the Nth poll sees.
answer() {
  local n=$1 state=$2
  shift 2
  local checks="[$(IFS=,; echo "$*")]"
  printf '{"state":"%s","url":"https://github.com/o/r/pull/7","statusCheckRollup":%s}' \
    "$state" "$checks" >"$QUEUE/$n"
}

@test "waits while open, then reports the merge and exits 0" {
  answer 1 OPEN '{"name":"ci","conclusion":""}'
  answer 2 OPEN '{"name":"ci","conclusion":"SUCCESS"}'
  answer 3 MERGED '{"name":"ci","conclusion":"SUCCESS"}'
  run "$SCRIPT" 7
  [ "$status" -eq 0 ]
  [ "$output" = "merged: https://github.com/o/r/pull/7" ]
}

@test "a PR closed without merging exits 3" {
  answer 1 CLOSED
  run "$SCRIPT" 7
  [ "$status" -eq 3 ]
  [ "$output" = "closed without merging: https://github.com/o/r/pull/7" ]
}

@test "a failing check ends the watch with its name and exits 1" {
  answer 1 OPEN '{"name":"lint","conclusion":"SUCCESS"}' '{"name":"e2e","conclusion":"FAILURE"}'
  run "$SCRIPT" 7
  [ "$status" -eq 1 ]
  [ "$output" = "check failed (e2e): https://github.com/o/r/pull/7" ]
}

@test "a commit status in error counts as a failed check" {
  answer 1 OPEN '{"context":"ci/legacy","state":"ERROR"}'
  run "$SCRIPT" 7
  [ "$status" -eq 1 ]
  [[ "$output" == "check failed (ci/legacy)"* ]]
}

@test "a passing or skipped check does not end the watch" {
  answer 1 OPEN '{"name":"e2e","conclusion":"SKIPPED"}' '{"name":"lint","conclusion":"NEUTRAL"}'
  answer 2 MERGED
  run "$SCRIPT" 7
  [ "$status" -eq 0 ]
}

@test "rides out a few failed polls" {
  echo ERR >"$QUEUE/1"
  echo ERR >"$QUEUE/2"
  answer 3 MERGED
  run "$SCRIPT" 7
  [ "$status" -eq 0 ]
}

@test "gives up with exit 4 when GitHub keeps failing" {
  echo ERR >"$QUEUE/1"
  run "$SCRIPT" 7
  [ "$status" -eq 4 ]
  [[ "$output" == *"giving up"* ]]
}

@test "without a PR argument prints usage and exits 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "while a check runs it is polled every 10 s, and a merge still ends the watch" {
  answer 1 OPEN '{"name":"ci","status":"IN_PROGRESS","conclusion":""}'
  answer 2 OPEN '{"context":"ext","state":"PENDING"}'
  answer 3 MERGED '{"context":"ext","state":"PENDING"}'
  run "$SCRIPT" 7
  [ "$status" -eq 0 ]
  [ "$(waits)" = "10 10" ]
}

@test "a PR that does not change is polled ever less often, up to a minute" {
  for n in 1 2 3 4 5; do answer "$n" OPEN '{"name":"ci","conclusion":""}'; done
  answer 6 MERGED
  run "$SCRIPT" 7
  [ "$status" -eq 0 ]
  [ "$(waits)" = "30 60 60 60 60" ]
}

@test "any change in the PR brings the wait back to 30 seconds" {
  answer 1 OPEN '{"name":"ci","conclusion":""}'
  answer 2 OPEN '{"name":"ci","conclusion":""}'
  answer 3 OPEN '{"name":"ci","conclusion":"SUCCESS"}'
  answer 4 OPEN '{"name":"ci","conclusion":"SUCCESS"}'
  answer 5 MERGED
  run "$SCRIPT" 7
  [ "$(waits)" = "30 60 30 60" ]
}

@test "failed polls back off the same way" {
  echo ERR >"$QUEUE/1"
  echo ERR >"$QUEUE/2"
  answer 3 MERGED
  run "$SCRIPT" 7
  [ "$(waits)" = "30 60" ]
}
