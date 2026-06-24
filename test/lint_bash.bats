#!/usr/bin/env bats

# Tests for bin/lint_bash.sh, which syntax-checks bash dotfiles (bash -n).
# Fixtures are passed as explicit arguments, so no git state is involved.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_bash.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a syntactically valid bash file" {
  printf 'alias ll="ls -la"\nexport PATH="$HOME/bin:$PATH"\n' >"$TMP/good.bash"
  run "$SCRIPT" "$TMP/good.bash"
  [ "$status" -eq 0 ]
}

@test "rejects a bash file with a syntax error" {
  printf 'if [ -n "$x" ]; then\n  echo hi\n' >"$TMP/bad.bash"   # missing fi
  run "$SCRIPT" "$TMP/bad.bash"
  [ "$status" -ne 0 ]
}

@test "fails the batch if any one file is broken" {
  printf 'echo ok\n' >"$TMP/ok.bash"
  printf 'for i in 1 2 3\n' >"$TMP/nope.bash"   # missing do/done
  run "$SCRIPT" "$TMP/ok.bash" "$TMP/nope.bash"
  [ "$status" -ne 0 ]
}

@test "no arguments and a clean repo exits 0 (repo's own .bashrc is valid)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
