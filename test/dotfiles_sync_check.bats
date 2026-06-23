#!/usr/bin/env bats

# Behavioural tests for bin/dotfiles_sync_check.sh, the shell-startup reminder
# that nags when the dotfiles repo is out of sync between machines.
#
# The script always inspects its OWN repo (dirname "$0"/..), so each test runs
# a *copy* of the script placed inside a throwaway git repo. That repo is wired
# to a local bare "remote" to exercise the ahead/behind branches without any
# network. XDG_CACHE_HOME is redirected into the temp dir and a fresh fetch
# stamp is pre-written so the script's once-per-24h background `git fetch`
# never fires (no network, no flakiness). Warnings go to stderr, which bats
# folds into $output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SRC="$REPO_ROOT/bin/dotfiles_sync_check.sh"
  TMP="$(mktemp -d)"
  export XDG_CACHE_HOME="$TMP/cache"

  REPO="$TMP/repo"
  mkdir -p "$REPO/bin"
  cp "$SRC" "$REPO/bin/dotfiles_sync_check.sh"
  SCRIPT="$REPO/bin/dotfiles_sync_check.sh"

  git -c init.defaultBranch=main init -q "$REPO"
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name "Test"
  echo seed >"$REPO/seed.txt"
  git -C "$REPO" add -A          # includes the copied bin/ script, so a fresh repo is clean
  git -C "$REPO" commit -qm "feat: seed"

  # Pre-stamp the fetch cache as "just fetched" so the script skips its
  # background git fetch entirely.
  mkdir -p "$XDG_CACHE_HOME/dotfiles"
  date +%s >"$XDG_CACHE_HOME/dotfiles/last_fetch"
}

teardown() {
  rm -rf "$TMP"
}

# Give $REPO a bare upstream and push main so @{upstream} is tracked.
add_upstream() {
  git init -q --bare "$TMP/remote.git"
  git -C "$REPO" remote add origin "$TMP/remote.git"
  git -C "$REPO" push -q -u origin main
}

@test "DOTFILES_NO_SYNC_CHECK short-circuits with no output" {
  echo dirty >>"$REPO/seed.txt"          # would otherwise warn
  DOTFILES_NO_SYNC_CHECK=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clean repo with no upstream is silent" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "warns about uncommitted changes" {
  echo dirty >>"$REPO/seed.txt"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "warns about untracked files too" {
  echo new >"$REPO/untracked.txt"
  run "$SCRIPT"
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "warns about unpushed commits when ahead of upstream" {
  add_upstream
  echo more >>"$REPO/seed.txt"
  git -C "$REPO" commit -qam "feat: ahead"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unpushed commit"* ]]
  [[ "$output" != *"behind upstream"* ]]
}

@test "warns when behind upstream" {
  add_upstream
  # Advance the remote from a second clone, then refresh our remote-tracking
  # ref (the script itself won't fetch — stamp is fresh), leaving HEAD behind.
  git clone -q -b main "$TMP/remote.git" "$TMP/other"
  git -C "$TMP/other" config user.email other@example.com
  git -C "$TMP/other" config user.name "Other"
  echo upstream >>"$TMP/other/seed.txt"
  git -C "$TMP/other" commit -qam "feat: upstream change"
  git -C "$TMP/other" push -q origin main
  git -C "$REPO" fetch -q origin

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"behind upstream"* ]]
  [[ "$output" != *"unpushed commit"* ]]
}
