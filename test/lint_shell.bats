#!/usr/bin/env bats

# Tests for bin/lint_shell.sh, which checks shell scripts (bash -n syntax +
# shellcheck). Fixtures are passed as explicit arguments, so no git state is
# involved and the script never falls back to scanning the repo. Mirrors
# lint_bash.bats / lint_zsh.bats so the shared lint gates all stay covered.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_shell.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a clean shell script" {
  printf '#!/bin/bash\nset -euo pipefail\necho "hello"\n' >"$TMP/good.sh"
  run "$SCRIPT" "$TMP/good.sh"
  [ "$status" -eq 0 ]
}

@test "rejects a script with a bash syntax error" {
  printf '#!/bin/bash\nif [ -n "$1" ]; then\n  echo hi\n' >"$TMP/bad.sh"   # missing fi
  run "$SCRIPT" "$TMP/bad.sh"
  [ "$status" -ne 0 ]
}

@test "rejects a script with a shellcheck violation" {
  # Syntactically valid, but SC2086 (unquoted variable expansion).
  printf '#!/bin/bash\nfiles=$1\nls $files\n' >"$TMP/sc.sh"
  run "$SCRIPT" "$TMP/sc.sh"
  [ "$status" -ne 0 ]
}

@test "fails the batch if any one file is broken" {
  printf '#!/bin/bash\necho ok\n' >"$TMP/ok.sh"
  printf '#!/bin/bash\ncase $x in\n' >"$TMP/nope.sh"   # missing patterns/esac
  run "$SCRIPT" "$TMP/ok.sh" "$TMP/nope.sh"
  [ "$status" -ne 0 ]
}

@test "skips arguments that no longer exist (staged deletion)" {
  run "$SCRIPT" "$TMP/deleted.sh"
  [ "$status" -eq 0 ]
}

@test "no arguments and a clean repo exits 0 (repo's own scripts pass)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
