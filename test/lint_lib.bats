#!/usr/bin/env bats

# Tests for bin/lint_lib.sh, the file selection every lint_*.sh shares.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/repo/bin"
  cp "$REPO_ROOT/bin/lint_lib.sh" "$TMP/repo/bin/"
  git -C "$TMP/repo" init -q
  printf 'a\n' >"$TMP/repo/a.lua"
  printf 'b\n' >"$TMP/repo/b.txt"
  git -C "$TMP/repo" add a.lua b.txt
}

teardown() {
  rm -rf "$TMP"
}

# Sources the lib from a subdirectory (it must cd to the repo root itself),
# runs lint_collect with the given args, and prints the selection.
collect() {
  mkdir -p "$TMP/repo/sub"
  (cd "$TMP/repo/sub" && set -euo pipefail && . ../bin/lint_lib.sh &&
    lint_collect "$@" && printf '%s\n' "${files[@]+"${files[@]}"}")
}

@test "with no args, selects tracked files matching the patterns" {
  run collect '*.lua' --
  [ "$status" -eq 0 ]
  [ "$output" = "a.lua" ]
}

@test "args win over the patterns, and missing paths are dropped" {
  run collect '*.lua' -- b.txt gone.lua
  [ "$status" -eq 0 ]
  [ "$output" = "b.txt" ]
}

@test "an arg list of only deleted paths selects nothing, without failing" {
  run collect '*.lua' -- gone.lua
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lint_require names the missing tool and exits 1" {
  run bash -c ". '$TMP/repo/bin/lint_lib.sh' && lint_require no-such-tool-xyz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-such-tool-xyz not found"* ]]
}
