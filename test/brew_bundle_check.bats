#!/usr/bin/env bats

# Behavioural tests for bin/brew_bundle_check.sh, the shell-startup reminder that
# nags when a Brewfile bundle has uninstalled packages.
#
# The script only prints the cached result of the *previous* check and refreshes
# the cache in a detached background job, so most tests assert in two steps: run
# once, wait_for the background refresh, then run again to observe the nag.
#
# Each test runs a *copy* of the script inside a throwaway repo with Brewfiles
# present and a stub `brew` on PATH whose exit code is scripted via
# BREW_CHECK_RC ("0" = satisfied, anything else = missing). XDG_CACHE_HOME is
# redirected into the temp dir so the 24h throttle stamp and the cached result
# file can be inspected and pre-seeded. Warnings go to stderr, which bats folds
# into $output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export XDG_CACHE_HOME="$TMP/cache"
  CACHE="$XDG_CACHE_HOME/dotfiles"

  REPO="$TMP/repo"
  mkdir -p "$REPO/bin"
  cp "$REPO_ROOT/bin/brew_bundle_check.sh" "$REPO/bin/brew_bundle_check.sh"
  chmod +x "$REPO/bin/brew_bundle_check.sh"
  SCRIPT="$REPO/bin/brew_bundle_check.sh"
  # The script checks these by name; their contents are irrelevant to the stub.
  for f in Brewfile.basic Brewfile.common Brewfile.macos Brewfile.linux; do
    echo "brew \"placeholder\"" >"$REPO/$f"
  done

  # Stub brew: `brew bundle check ...` exits with BREW_CHECK_RC (default 0).
  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
if [ "$1" = "bundle" ] && [ "$2" = "check" ]; then
  exit "${BREW_CHECK_RC:-0}"
fi
exit 0
STUBEOF
  chmod +x "$STUB/brew"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
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

@test "DOTFILES_NO_BREW_CHECK short-circuits with no output" {
  BREW_CHECK_RC=1 DOTFILES_NO_BREW_CHECK=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when brew is not installed" {
  # Run with a PATH that has neither the stub nor a real brew.
  PATH="/nonexistent" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "first run is silent and populates the cache in the background" {
  BREW_CHECK_RC=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  wait_for '[ -s "$CACHE/brew_missing" ]'
  [ -f "$CACHE/last_brew_check" ]
}

@test "silent when all bundles are satisfied" {
  BREW_CHECK_RC=0 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # The result cache exists but is empty.
  wait_for '[ -f "$CACHE/brew_missing" ]'
  [ ! -s "$CACHE/brew_missing" ]
  # Warm cache: still silent.
  BREW_CHECK_RC=0 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "warns from the cached result and names the unsatisfied bundle" {
  BREW_CHECK_RC=1 run "$SCRIPT"
  wait_for '[ -s "$CACHE/brew_missing" ]'
  BREW_CHECK_RC=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[brew]"* ]]
  [[ "$output" == *"Brewfile.basic"* ]]
  [[ "$output" == *"brew bundle install --file="* ]]
}

@test "reuses the cached nag within 24h without re-checking" {
  BREW_CHECK_RC=1 run "$SCRIPT"
  wait_for '[ -s "$CACHE/brew_missing" ]'
  # Within 24h the stub flipping to "satisfied" must NOT change the cached nag.
  BREW_CHECK_RC=0 run "$SCRIPT"
  [[ "$output" == *"Brewfile.basic"* ]]
  # Give a rogue background re-check time to clear the cache; it must not have.
  sleep 1
  [ -s "$CACHE/brew_missing" ]
}

@test "re-checks in the background once the stamp is older than 24h" {
  BREW_CHECK_RC=1 run "$SCRIPT" # seed a "missing" cache
  wait_for '[ -s "$CACHE/brew_missing" ]'

  # Backdate the stamp beyond 24h; a now-satisfied check clears the nag, but
  # only for the *next* shell — this session still shows the stale nag.
  echo "$(( $(date +%s) - 90000 ))" >"$CACHE/last_brew_check"
  BREW_CHECK_RC=0 run "$SCRIPT"
  [[ "$output" == *"Brewfile.basic"* ]]
  wait_for '[ ! -s "$CACHE/brew_missing" ]'
  BREW_CHECK_RC=0 run "$SCRIPT"
  [ -z "$output" ]
}

@test "startup does not block on a slow brew bundle check" {
  # Stub sleeps 3s per bundle check; the foreground script must return before
  # even a single check could have finished.
  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
if [ "$1" = "bundle" ] && [ "$2" = "check" ]; then
  sleep 3
  exit 1
fi
exit 0
STUBEOF
  chmod +x "$STUB/brew"

  start=$(date +%s)
  "$SCRIPT" >/dev/null 2>&1
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -lt 3 ]
}
