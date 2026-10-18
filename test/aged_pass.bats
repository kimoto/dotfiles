#!/usr/bin/env bats

# Tests for ci/aged_pass.sh with a stub `gh` that applies the script's --jq
# filter to a canned list of workflow runs.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/ci/aged_pass.sh"
  TMP="$(mktemp -d)"
  export RUNS="$TMP/runs.json"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/gh" <<'STUB'
#!/bin/bash
while [ "$#" -gt 0 ]; do
  [ "$1" = --jq ] && { jq -r "$2" "$RUNS"; exit; }
  shift
done
STUB
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"
  export GITHUB_REPOSITORY=owner/repo
}

teardown() {
  rm -rf "$TMP"
}

ago() { date -u -d "-$1 days" +%Y-%m-%dT%H:%M:%SZ; }

runs() {
  printf '{"workflow_runs":[%s]}' "$(IFS=,; echo "$*")" >"$RUNS"
}
run_of() { printf '{"head_sha":"%s","created_at":"%s","event":"%s"}' "$1" "$(ago "$2")" "$3"; }

@test "picks the newest pass that is at least a week old" {
  runs "$(run_of new 1 schedule)" "$(run_of week 8 schedule)" "$(run_of old 20 schedule)"
  run "$SCRIPT" wf.yml 7 schedule
  [ "$status" -eq 0 ]
  [ "$output" = week ]
}

@test "prints nothing when no pass is old enough" {
  runs "$(run_of new 1 schedule)" "$(run_of newer 0 schedule)"
  run "$SCRIPT" wf.yml 7 schedule
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores runs from events that do not count" {
  runs "$(run_of cached 8 workflow_dispatch)" "$(run_of fresh 10 schedule)"
  run "$SCRIPT" wf.yml 7 schedule
  [ "$output" = fresh ]
}

@test "counts every event it is given" {
  runs "$(run_of manual 8 workflow_dispatch)" "$(run_of sched 10 schedule)"
  run "$SCRIPT" wf.yml 7 schedule workflow_dispatch
  [ "$output" = manual ]
}

@test "refuses to run without any event" {
  run "$SCRIPT" wf.yml 7
  [ "$status" -eq 2 ]
}
