#!/usr/bin/env bats

# Tests for bin/lint_zsh.sh, which syntax-checks zsh files (zsh -n).
# Fixtures are passed as explicit arguments, so no git state is involved and
# the script never falls back to scanning the repo. Mirrors lint_bash.bats /
# lint_lua.bats so the three syntax linters stay symmetric.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_zsh.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a syntactically valid zsh file" {
  printf 'alias ll="ls -la"\nfor f in a b c; do print -- "$f"; done\n' >"$TMP/good.zsh"
  run "$SCRIPT" "$TMP/good.zsh"
  [ "$status" -eq 0 ]
}

@test "rejects a zsh file with a syntax error" {
  printf 'if [[ -n "$x" ]]; then\n  print hi\n' >"$TMP/bad.zsh"   # missing fi
  run "$SCRIPT" "$TMP/bad.zsh"
  [ "$status" -ne 0 ]
}

@test "fails the batch if any one file is broken" {
  printf 'print ok\n' >"$TMP/ok.zsh"
  printf 'case $x in\n' >"$TMP/nope.zsh"   # missing patterns/esac
  run "$SCRIPT" "$TMP/ok.zsh" "$TMP/nope.zsh"
  [ "$status" -ne 0 ]
}

@test "no arguments and a clean repo exits 0 (repo's own zsh is valid)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
