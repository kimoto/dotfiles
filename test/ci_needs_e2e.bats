#!/usr/bin/env bats

# Tests for bin/ci_needs_e2e.sh, which lets CI skip the e2e jobs for a branch
# that only touches prose. Each case builds a throwaway repo with a `main`
# branch as the base, so no fixture depends on this repository's history.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SCRIPT="$REPO_ROOT/bin/ci_needs_e2e.sh"
  TMP="$(mktemp -d)"
  cd "$TMP"
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  printf 'x\n' >.zshrc
  printf 'x\n' >README.md
  printf 'x\n' >KEYBINDINGS.md
  git add . && git commit -q -m "chore: root"
  git switch -qc topic
}

teardown() {
  cd /
  rm -rf "$TMP"
}

commit_change() {
  mkdir -p "$(dirname "$1")"
  printf 'y\n' >>"$1"
  git add "$1" && git commit -q -m "chore: change $1"
}

@test "a branch that only touches Markdown skips e2e" {
  commit_change README.md
  commit_change docs/note.md
  run "$SCRIPT" main
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "a code change anywhere on the branch runs e2e" {
  commit_change README.md
  commit_change .zshrc
  run "$SCRIPT" main
  [ "$output" = "true" ]
}

@test "an earlier code push still counts after a later docs-only push" {
  commit_change .zshrc
  commit_change README.md
  run "$SCRIPT" main
  [ "$output" = "true" ]
}

@test "KEYBINDINGS.md runs e2e: scripts and the keys test parse it" {
  commit_change KEYBINDINGS.md
  run "$SCRIPT" main
  [ "$output" = "true" ]
}

@test "renaming code into a .md file runs e2e" {
  git mv .zshrc old.md
  git commit -q -m "chore: rename"
  run "$SCRIPT" main
  [ "$output" = "true" ]
}

@test "no change against the base (a push to main) runs e2e" {
  git switch -q main
  run "$SCRIPT" main
  [ "$output" = "true" ]
}

@test "a base that cannot be resolved runs e2e" {
  commit_change README.md
  run "$SCRIPT" no-such-ref
  [ "$output" = "true" ]
}
