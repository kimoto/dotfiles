#!/usr/bin/env bats

# Behavioural tests for bin/dotfiles_sync_check.sh, the shell-startup reminder
# that nags when the dotfiles repo is out of sync between machines.
#
# The script only prints the cached result of the *previous* run and recomputes
# the state in a detached background job (same design as brew_bundle_check.sh),
# so most tests assert in two steps: run once, wait_for the background refresh,
# then run again to observe the nag.
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
  CACHE="$XDG_CACHE_HOME/dotfiles"

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
  # A detached background refresh may still be recreating git lock files under
  # $TMP while we delete it; retry until the tree stays gone.
  for _ in $(seq 1 20); do
    rm -rf "$TMP" 2>/dev/null
    [ ! -e "$TMP" ] && return 0
    sleep 0.1
  done
  rm -rf "$TMP"
}

# Give $REPO a bare upstream and push main so @{upstream} is tracked.
add_upstream() {
  git init -q --bare "$TMP/remote.git"
  git -C "$REPO" remote add origin "$TMP/remote.git"
  git -C "$REPO" push -q -u origin main
}

# Poll until the condition holds (~5s timeout) — the detached background
# refresh leaves no process handle to wait on.
wait_for() {
  for _ in $(seq 1 50); do
    eval "$1" && return 0
    sleep 0.1
  done
  echo "timed out waiting for: $1" >&2
  return 1
}

@test "DOTFILES_NO_SYNC_CHECK short-circuits with no output" {
  echo dirty >>"$REPO/seed.txt"          # would otherwise warn
  DOTFILES_NO_SYNC_CHECK=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # And no background job was spawned either.
  sleep 1
  [ ! -f "$CACHE/sync_status" ]
}

@test "first run is silent and populates the cache in the background" {
  echo dirty >>"$REPO/seed.txt"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  wait_for '[ -s "$CACHE/sync_status" ]'
}

@test "clean repo with no upstream stays silent across runs" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # The result cache exists but is empty.
  wait_for '[ -f "$CACHE/sync_status" ]'
  [ ! -s "$CACHE/sync_status" ]
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "warns about uncommitted changes" {
  echo dirty >>"$REPO/seed.txt"
  run "$SCRIPT"
  wait_for '[ -s "$CACHE/sync_status" ]'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "warns about untracked files too" {
  echo new >"$REPO/untracked.txt"
  run "$SCRIPT"
  wait_for '[ -s "$CACHE/sync_status" ]'
  run "$SCRIPT"
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "warns about unpushed commits when ahead of upstream" {
  add_upstream
  echo more >>"$REPO/seed.txt"
  git -C "$REPO" commit -qam "feat: ahead"
  run "$SCRIPT"
  wait_for '[ -s "$CACHE/sync_status" ]'
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
  wait_for '[ -s "$CACHE/sync_status" ]'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"behind upstream"* ]]
  [[ "$output" != *"unpushed commit"* ]]
}

@test "stale warning clears one run after the repo becomes clean" {
  echo dirty >>"$REPO/seed.txt"
  run "$SCRIPT"
  wait_for '[ -s "$CACHE/sync_status" ]'
  # Repo becomes clean; this run still shows the (stale) cached warning.
  git -C "$REPO" checkout -q -- seed.txt
  run "$SCRIPT"
  [[ "$output" == *"uncommitted changes"* ]]
  wait_for '[ ! -s "$CACHE/sync_status" ]'
  run "$SCRIPT"
  [ -z "$output" ]
}

@test "startup does not block on a slow git" {
  # Stub git: any invocation sleeps 3s. The foreground must return before even
  # a single git call could have finished.
  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  printf '#!/bin/bash\nsleep 3\nexit 0\n' >"$STUB/git"
  chmod +x "$STUB/git"

  start=$(date +%s)
  PATH="$STUB:$PATH" "$SCRIPT" >/dev/null 2>&1
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -lt 3 ]
}
