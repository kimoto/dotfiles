#!/usr/bin/env bats

# Tests for bin/lint_python.sh, which runs ruff's default rules on Python files.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_python.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a clean file" {
  printf 'import os\n\nprint(os.getcwd())\n' >"$TMP/good.py"
  run "$SCRIPT" "$TMP/good.py"
  [ "$status" -eq 0 ]
}

@test "rejects an unused import" {
  printf 'import os\n' >"$TMP/bad.py"
  run "$SCRIPT" "$TMP/bad.py"
  [ "$status" -ne 0 ]
  [[ "$output" == *"F401"* ]]
}

@test "rejects a syntax error" {
  printf 'def f(:\n' >"$TMP/broken.py"
  run "$SCRIPT" "$TMP/broken.py"
  [ "$status" -ne 0 ]
}

@test "no arguments checks every tracked .py and passes" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
