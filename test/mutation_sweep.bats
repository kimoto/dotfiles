#!/usr/bin/env bats

# mutation_sweep.sh is only useful if its two answers are right: a failure
# exit the tests watch is "killed", one they miss is "survived". It edits real
# files in place, so it also has to put every one back, even when cut short.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/bin" "$REPO/test"
  cp "$REPO_ROOT/bin/mutation_sweep.sh" "$REPO_ROOT/bin/run_tests.sh" \
    "$REPO_ROOT/bin/git_fixture_helpers.sh" "$REPO/bin/"
  cat >"$REPO/bin/target.sh" <<'SH'
#!/bin/bash
BASE=$(cd "$(dirname "$0")" || exit 1; pwd)
[ "${1:-}" = watched ] && exit 1
[ "${1:-}" = missed ] && exit 1
# exit 1 in a comment
exit 0
SH
  # Only the "watched" exit has a test; the runner below stands in for bats.
  echo '# names target.sh' >"$REPO/test/target.bats"
  cat >"$REPO/runner" <<'SH'
#!/bin/bash
"$(dirname "$0")/bin/target.sh" watched
[ $? -eq 1 ]
SH
  chmod +x "$REPO/bin/"*.sh "$REPO/runner"
  ORIG="$(cat "$REPO/bin/target.sh")"
}

sweep() { (cd "$REPO" && MUTATION_RUNNER="$REPO/runner" ./bin/mutation_sweep.sh "$@"); }

@test "an exit the tests watch is killed, one they miss survives" {
  run sweep bin/target.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"killed bin/target.sh:3"* ]]
  [[ "$output" == *"survived bin/target.sh:4"* ]]
  [[ "$output" == *"== 1 survived, 1 killed =="* ]]
}

@test "cd guards and comments are not mutated" {
  run sweep bin/target.sh
  [[ "$output" != *"target.sh:2"* ]]
  [[ "$output" != *"target.sh:5"* ]]
}

@test "every mutant is put back" {
  sweep bin/target.sh
  [ "$(cat "$REPO/bin/target.sh")" = "$ORIG" ]
}

@test "a script no test names is reported, not run" {
  printf '#!/bin/bash\nexit 1\n' >"$REPO/bin/lonely.sh"
  run sweep bin/lonely.sh
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "untested bin/lonely.sh" ]
}
