#!/usr/bin/env bats

# Tests for bin/check_commit_msgs_range.sh, the CI-side Conventional Commits
# net. Each case builds a throwaway git repo and validates an explicit range,
# so no fixture depends on this repository's own history.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_commit_msgs_range.sh"
  TMP="$(mktemp -d)"
  cd "$TMP"
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  git commit -q --allow-empty -m "chore: root"
  git branch -q base
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "passes when every commit in the range is conventional" {
  git commit -q --allow-empty -m "feat(zsh): add thing"
  git commit -q --allow-empty -m "fix: correct thing"
  run "$SCRIPT" base..HEAD
  [ "$status" -eq 0 ]
}

@test "fails and names the offending commit" {
  git commit -q --allow-empty -m "feat: fine"
  git commit -q --allow-empty -m "added stuff without a type"
  bad="$(git rev-parse HEAD)"
  run "$SCRIPT" base..HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not a valid Conventional Commits message"* ]]
  [[ "$output" == *"$bad"* ]]
}

@test "merge subjects are exempt (git generates them)" {
  git switch -qc topic
  git commit -q --allow-empty -m "feat: on topic"
  git switch -q main
  git commit -q --allow-empty -m "feat: on main"
  git merge -q --no-ff -m "Merge branch 'topic'" topic
  run "$SCRIPT" base..HEAD
  [ "$status" -eq 0 ]
}

@test "an empty range is a pass (push to main)" {
  run "$SCRIPT" HEAD..HEAD
  [ "$status" -eq 0 ]
}
