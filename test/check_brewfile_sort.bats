#!/usr/bin/env bats

# Tests for bin/check_brewfile_sort.sh.
#
# The script must accept Brewfiles whose tap/brew/cask entries are sorted A-Z
# (case-insensitive) and reject any section that is out of order. With no
# arguments it checks the repo's own Brewfiles; with arguments it checks the
# given files (used here to feed fixtures).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_brewfile_sort.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "the repo's own Brewfiles are sorted" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "accepts a correctly sorted Brewfile" {
  printf 'brew "alpha"\nbrew "bravo"\nbrew "charlie"\n' >"$TMP/Brewfile.sorted"
  run "$SCRIPT" "$TMP/Brewfile.sorted"
  [ "$status" -eq 0 ]
}

@test "rejects an out-of-order Brewfile" {
  printf 'brew "charlie"\nbrew "alpha"\n' >"$TMP/Brewfile.bad"
  run "$SCRIPT" "$TMP/Brewfile.bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not sorted"* ]]
}

@test "sort is case-insensitive" {
  printf 'brew "Alpha"\nbrew "bravo"\nbrew "Charlie"\n' >"$TMP/Brewfile.case"
  run "$SCRIPT" "$TMP/Brewfile.case"
  [ "$status" -eq 0 ]
}

@test "checks tap/brew/cask sections independently" {
  printf 'tap "z/last"\ntap "a/first"\nbrew "alpha"\n' >"$TMP/Brewfile.sections"
  run "$SCRIPT" "$TMP/Brewfile.sections"
  [ "$status" -eq 1 ]
}
