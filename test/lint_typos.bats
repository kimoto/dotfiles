#!/usr/bin/env bats

# Tests for bin/lint_typos.sh, which runs typos with the repo's _typos.toml.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_typos.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a correctly spelled file" {
  printf 'a correctly spelled line\n' >"$TMP/good.txt"
  run "$SCRIPT" "$TMP/good.txt"
  [ "$status" -eq 0 ]
}

@test "rejects a known misspelling" {
  # Assembled at run time, or the no-argument walk below would flag this file.
  printf '%s quick brown fox\n' "t""eh" >"$TMP/bad.txt"
  run "$SCRIPT" "$TMP/bad.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"should be"* ]]
}

@test "allows the words _typos.toml lists" {
  printf '[ a -ot b ] (ba)sh <leader>fo\n' >"$TMP/allowed.txt"
  run "$SCRIPT" "$TMP/allowed.txt"
  [ "$status" -eq 0 ]
}

@test "no arguments walks the whole repo and passes" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
