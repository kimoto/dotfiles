#!/usr/bin/env bats

# Tests for bin/routine_labels.sh with a stub `gh` that serves a canned label
# list and records every write.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/routine_labels.sh"
  TMP="$(mktemp -d)"
  export LABELS="$TMP/labels.tsv" CALLS="$TMP/calls"
  : >"$LABELS"
  : >"$CALLS"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/gh" <<'STUB'
#!/bin/bash
case " $* " in
  *" --paginate "*) cat "$LABELS" ;;
  *) echo "$*" >>"$CALLS" ;;
esac
STUB
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "recolours routine labels that drifted and leaves the right ones alone" {
  printf 'routine\t1d76db\nroutine:test-sweep\tededed\nroutine:prune-sweep\td4c5f9\n' >"$LABELS"
  run "$SCRIPT" --repo o/r
  [ "$status" -eq 0 ]
  run cat "$CALLS"
  [ "${lines[0]}" = "api -X PATCH repos/o/r/labels/routine -f color=5319e7" ]
  [ "${lines[1]}" = "api -X PATCH repos/o/r/labels/routine%3Atest-sweep -f color=d4c5f9" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "creates the parent and a named routine label when missing" {
  run "$SCRIPT" --repo o/r routine:refactor-sweep
  [ "$status" -eq 0 ]
  run cat "$CALLS"
  [ "${lines[0]}" = "api -X POST repos/o/r/labels -f name=routine -f color=5319e7" ]
  [ "${lines[1]}" = "api -X POST repos/o/r/labels -f name=routine:refactor-sweep -f color=d4c5f9" ]
}

@test "does nothing when every label is already right" {
  printf 'routine\t5319e7\nroutine:test-sweep\td4c5f9\n' >"$LABELS"
  run "$SCRIPT" --repo o/r routine:test-sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]
}

@test "dry run reports but writes nothing" {
  printf 'routine\tededed\n' >"$LABELS"
  run "$SCRIPT" --dry-run --repo o/r
  [ "$status" -eq 0 ]
  [[ "$output" == *"recolour routine ededed -> 5319e7"* ]]
  [ ! -s "$CALLS" ]
}

@test "refuses a label outside the routine family" {
  run "$SCRIPT" --repo o/r bug
  [ "$status" -eq 2 ]
  [ ! -s "$CALLS" ]
}
