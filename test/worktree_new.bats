#!/usr/bin/env bats

# Tests for bin/worktree_new.sh, which cuts a linked worktree off the *remote*
# default branch so a second, parallel line of work can start without touching
# the primary checkout.
#
# The fixture is a clone of a bare "origin", because the whole point of the
# script is where it branches from: every case that matters is about the base
# commit being origin/main rather than whatever HEAD happens to be.
#
# stdout carries the path and nothing else — the zsh `W` helper cd's into
# "$(worktree_new.sh ...)", so a stray progress line would become a directory
# name. Several cases assert that split explicitly.

# `run --separate-stderr` is a 1.5.0 flag; without this it only warns and the
# two streams stay merged, which is exactly what those cases are testing apart.
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SCRIPT="$REPO_ROOT/bin/worktree_new.sh"
  TMP="$(fixture_tmpdir)"

  ORIGIN="$TMP/origin.git"
  git init -q --bare -b main "$ORIGIN"

  SEED="$TMP/seed"
  git init -q -b main "$SEED"
  git -C "$SEED" config user.email t@t.test
  git -C "$SEED" config user.name test
  git -C "$SEED" commit -q --allow-empty -m "feat: init"
  git -C "$SEED" remote add origin "$ORIGIN"
  git -C "$SEED" -c push.negotiate=false push -q origin main

  REPO="$TMP/repo"
  git clone -q "$ORIGIN" "$REPO"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name test

  export DOTFILES_WORKTREE_ROOT="$TMP/worktrees"
}

teardown() {
  rm -rf "$TMP"
}

# --- argument handling -----------------------------------------------------

@test "usage: no branch name is a usage error, not a guess" {
  cd "$REPO"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "usage: rejects a branch without a Conventional-Commits type prefix" {
  cd "$REPO"
  run "$SCRIPT" my-branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"<type>/<short-desc>"* ]]
}

@test "usage: rejects an unknown type prefix" {
  cd "$REPO"
  run "$SCRIPT" wip/thing
  [ "$status" -eq 1 ]
}

@test "usage: accepts every documented type" {
  cd "$REPO"
  for type in feat fix chore docs refactor ci test revert; do
    run "$SCRIPT" "$type/thing-$type"
    [ "$status" -eq 0 ]
  done
}

@test "refuses to run outside a git repository" {
  cd "$TMP"
  run "$SCRIPT" feat/thing
  [ "$status" -ne 0 ]
  # Named, not just non-zero: a missing script also exits non-zero, and that
  # would leave this case passing forever without the script existing.
  [[ "$output" == *"not a git repository"* ]]
}

# --- what it creates -------------------------------------------------------

@test "creates the worktree under the root, one directory per repo" {
  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  [ -d "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" ]
  [ -e "$DOTFILES_WORKTREE_ROOT/repo/feat-thing/.git" ]
}

@test "prints the path on stdout and nothing else" {
  cd "$REPO"
  run --separate-stderr "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  [ "$output" = "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" ]
}

@test "the new worktree is on the requested branch" {
  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  run git -C "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" branch --show-current
  [ "$output" = "feat/thing" ]
}

@test "branches off origin's default branch, not the current HEAD" {
  # Put a commit on the local checkout that origin has never seen. A worktree
  # cut from HEAD would carry it; one cut from origin/main must not.
  git -C "$REPO" switch -q -c chore/local-detour
  git -C "$REPO" commit -q --allow-empty -m "chore: local only"
  local stray
  stray=$(git -C "$REPO" rev-parse HEAD)

  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]

  run git -C "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" rev-parse HEAD
  [ "$output" != "$stray" ]
  [ "$output" = "$(git -C "$REPO" rev-parse origin/main)" ]
}

@test "picks up commits pushed to origin after the clone" {
  git -C "$SEED" commit -q --allow-empty -m "feat: newer"
  git -C "$SEED" -c push.negotiate=false push -q origin main
  local newest
  newest=$(git -C "$SEED" rev-parse HEAD)

  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]

  run git -C "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" rev-parse HEAD
  [ "$output" = "$newest" ]
}

@test "leaves the primary checkout on the branch it was on" {
  git -C "$REPO" switch -q -c chore/staying-put
  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  run git -C "$REPO" branch --show-current
  [ "$output" = "chore/staying-put" ]
}

# --- running it twice ------------------------------------------------------

@test "a second run returns the same path instead of failing" {
  cd "$REPO"
  run --separate-stderr "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  local first="$output"

  run --separate-stderr "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "a second run does not reset work already done in the worktree" {
  cd "$REPO"
  run --separate-stderr "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  local wt="$output"
  git -C "$wt" commit -q --allow-empty -m "feat: work in progress"
  local wip
  wip=$(git -C "$wt" rev-parse HEAD)

  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  run git -C "$wt" rev-parse HEAD
  [ "$output" = "$wip" ]
}

@test "refuses a branch already checked out in the primary checkout" {
  git -C "$REPO" switch -q -c feat/thing
  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -ne 0 ]
  [[ "$output" == *"already checked out"* ]]
}

# --- reusing an existing branch --------------------------------------------

@test "reuses an existing local branch rather than moving it" {
  git -C "$REPO" branch feat/thing origin/main
  git -C "$REPO" switch -q feat/thing
  git -C "$REPO" commit -q --allow-empty -m "feat: earlier work"
  local earlier
  earlier=$(git -C "$REPO" rev-parse HEAD)
  git -C "$REPO" switch -q main

  cd "$REPO"
  run "$SCRIPT" feat/thing
  [ "$status" -eq 0 ]
  run git -C "$DOTFILES_WORKTREE_ROOT/repo/feat-thing" rev-parse HEAD
  [ "$output" = "$earlier" ]
}
