#!/usr/bin/env bats

# Tests for bin/protect_main.sh, the guard the lefthook pre-commit and pre-push
# hooks call to keep work off the 'main' branch.
#
#   commit mode -> inspects `git rev-parse --abbrev-ref HEAD` of the CWD, so
#                  each case cd's into a throwaway git repo on a chosen branch.
#   push mode   -> parses git's pre-push stdin (<local-ref> <local-sha>
#                  <remote-ref> <remote-sha> per line); pure text, no git state.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/protect_main.sh"
  TMP="$(mktemp -d)"

  REPO="$TMP/repo"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name test
  git -C "$REPO" commit -q --allow-empty -m "feat: init"
}

teardown() {
  rm -rf "$TMP"
}

# --- commit mode -----------------------------------------------------------

@test "commit: blocks a commit while HEAD is main" {
  cd "$REPO"
  run "$SCRIPT" commit
  [ "$status" -eq 1 ]
  [[ "$output" == *"Direct commits to 'main' are blocked"* ]]
}

@test "commit: allows a commit on a feature branch" {
  git -C "$REPO" switch -q -c feat/thing
  cd "$REPO"
  run "$SCRIPT" commit
  [ "$status" -eq 0 ]
}

# --- push mode -------------------------------------------------------------

@test "push: blocks a push whose remote ref is refs/heads/main" {
  run bash -c \
    'printf "%s\n" "refs/heads/main abc refs/heads/main def" | "$1" push' _ "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Direct push to 'main' is blocked"* ]]
}

@test "push: allows a push to a non-main remote ref" {
  run bash -c \
    'printf "%s\n" "refs/heads/feat abc refs/heads/feat def" | "$1" push' _ "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "push: blocks if any one of several pushed refs targets main" {
  feed='refs/heads/feat abc refs/heads/feat def
refs/heads/x abc refs/heads/main def'
  run bash -c 'printf "%s\n" "$2" | "$1" push' _ "$SCRIPT" "$feed"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Direct push to 'main' is blocked"* ]]
}

@test "push: empty stdin (nothing to push) exits 0" {
  run bash -c 'printf "" | "$1" push' _ "$SCRIPT"
  [ "$status" -eq 0 ]
}

# --- usage -----------------------------------------------------------------

@test "errors out on an unknown mode" {
  run "$SCRIPT" bogus
  [ "$status" -eq 2 ]
}

@test "errors out with no mode" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
