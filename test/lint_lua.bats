#!/usr/bin/env bats

# Tests for bin/lint_lua.sh, which parse-checks Lua files with `luajit -b`.
# Fixtures are passed as explicit arguments (absolute paths), so no git state
# is involved and the script never falls back to scanning the repo.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_lua.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a syntactically valid Lua file" {
  printf 'local t = { a = 1 }\nreturn t\n' >"$TMP/good.lua"
  run "$SCRIPT" "$TMP/good.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/good.lua"* ]]
}

@test "rejects a Lua file with a syntax error" {
  printf 'local x = \n' >"$TMP/bad.lua"
  run "$SCRIPT" "$TMP/bad.lua"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lua syntax check failed: $TMP/bad.lua"* ]]
}

@test "fails the batch if any one file is broken" {
  printf 'return 1\n' >"$TMP/ok.lua"
  printf 'function(\n' >"$TMP/nope.lua"
  run "$SCRIPT" "$TMP/ok.lua" "$TMP/nope.lua"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok $TMP/ok.lua"* ]]
  [[ "$output" == *"lua syntax check failed: $TMP/nope.lua"* ]]
}

@test "no arguments and a clean repo exits 0 (repo's own Lua is valid)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "the repo's own tracked Lua files all pass" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config/nvim/init.lua"* ]]
}
