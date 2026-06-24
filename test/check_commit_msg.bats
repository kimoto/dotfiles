#!/usr/bin/env bats

# Tests for bin/check_commit_msg.sh, the Conventional Commits validator the
# lefthook commit-msg hook calls. The message is read from a file (git passes
# the commit-msg path), so each case writes a one-line fixture and feeds its
# path. Only the subject line is validated.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_commit_msg.sh"
  TMP="$(mktemp -d)"
  MSG="$TMP/msg"
}

teardown() {
  rm -rf "$TMP"
}

# Write $1 as the commit subject and run the script against it.
check() {
  printf '%s\n' "$1" >"$MSG"
  run "$SCRIPT" "$MSG"
}

@test "accepts a plain type: description" {
  check "feat: add opacity toggle"
  [ "$status" -eq 0 ]
}

@test "accepts a type(scope): description" {
  check "fix(ghostty): correct keybind"
  [ "$status" -eq 0 ]
}

@test "accepts a breaking-change marker type(scope)!: description" {
  check "refactor(zsh)!: drop legacy loader"
  [ "$status" -eq 0 ]
}

@test "accepts every allowed type" {
  for t in feat fix chore docs refactor ci test revert; do
    check "$t: something"
    [ "$status" -eq 0 ] || { echo "type '$t' was rejected"; return 1; }
  done
}

@test "rejects an unknown type" {
  check "wip: half-done thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not a valid Conventional Commits message"* ]]
}

@test "rejects a missing colon/description" {
  check "feat add a thing"
  [ "$status" -eq 1 ]
}

@test "rejects an empty description after the colon" {
  check "feat: "
  [ "$status" -eq 1 ]
}

@test "rejects an uppercase scope" {
  check "feat(Ghostty): add thing"
  [ "$status" -eq 1 ]
}

@test "exempts a Merge subject" {
  check "Merge branch 'main' into feature"
  [ "$status" -eq 0 ]
}

@test "exempts a Revert subject" {
  check 'Revert "feat: add a thing"'
  [ "$status" -eq 0 ]
}

@test "exempts a fixup! subject" {
  check "fixup! feat: add a thing"
  [ "$status" -eq 0 ]
}

@test "only the first line is checked (a bad body is ignored)" {
  printf 'feat: good subject\n\nthis body line is not conventional\n' >"$MSG"
  run "$SCRIPT" "$MSG"
  [ "$status" -eq 0 ]
}

@test "errors out when given no argument" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
