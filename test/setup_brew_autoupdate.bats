#!/usr/bin/env bats

# Behavioural tests for bin/setup_brew_autoupdate.sh, which enables the
# homebrew/autoupdate launchd agent on macOS. The script shells out to `brew`
# and `uname`, so each test puts stubs on PATH: `uname` reports the OS via
# STUB_UNAME, and `brew` records every invocation to BREW_LOG and answers
# `autoupdate status` from STUB_RUNNING. No real Homebrew or launchd is touched.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  SCRIPT="$REPO_ROOT/bin/setup_brew_autoupdate.sh"
  BREW_LOG="$TMP/brew.log"
  export BREW_LOG

  STUB="$TMP/stubbin"
  mkdir -p "$STUB"

  cat >"$STUB/uname" <<'STUBEOF'
#!/bin/bash
echo "${STUB_UNAME:-Darwin}"
STUBEOF

  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
echo "brew $*" >>"$BREW_LOG"
if [ "$1" = "tap" ] && [ "$#" -eq 1 ]; then
  if [ "${STUB_DOMT4_TAPPED:-0}" = "1" ]; then
    echo "domt4/autoupdate"
  fi
  echo "homebrew/autoupdate"
  exit 0
fi
if [ "$1" = "autoupdate" ] && [ "$2" = "status" ]; then
  if [ "${STUB_RUNNING:-0}" = "1" ]; then
    echo "Autoupdate is installed and running."
  else
    echo "Autoupdate is not configured."
  fi
fi
exit 0
STUBEOF

  chmod +x "$STUB/uname" "$STUB/brew"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "no-op on non-macOS (no brew calls)" {
  STUB_UNAME=Linux run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping on non-macOS"* ]]
  [ ! -f "$BREW_LOG" ]
}

@test "on macOS with nothing scheduled, taps and starts with the right flags" {
  STUB_UNAME=Darwin STUB_RUNNING=0 run "$SCRIPT"
  [ "$status" -eq 0 ]
  run cat "$BREW_LOG"
  [[ "$output" == *"brew tap homebrew/autoupdate"* ]]
  [[ "$output" == *"brew autoupdate start 604800 --upgrade --cleanup"* ]]
}

@test "untaps a leftover untrusted domt4/autoupdate tap before tapping the official one" {
  STUB_UNAME=Darwin STUB_RUNNING=0 STUB_DOMT4_TAPPED=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  run cat "$BREW_LOG"
  [[ "$output" == *"brew untap domt4/autoupdate"* ]]
}

@test "does not untap anything when domt4/autoupdate is not present" {
  STUB_UNAME=Darwin STUB_RUNNING=0 run "$SCRIPT"
  run cat "$BREW_LOG"
  [[ "$output" != *"untap"* ]]
}

@test "does not pass --sudo (casks needing a password stay manual)" {
  STUB_UNAME=Darwin STUB_RUNNING=0 run "$SCRIPT"
  run cat "$BREW_LOG"
  [[ "$output" != *"--sudo"* ]]
}

@test "idempotent: already running means no start call" {
  STUB_UNAME=Darwin STUB_RUNNING=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
  run cat "$BREW_LOG"
  [[ "$output" != *"autoupdate start"* ]]
}

@test "honours a custom interval via BREW_AUTOUPDATE_INTERVAL" {
  STUB_UNAME=Darwin STUB_RUNNING=0 BREW_AUTOUPDATE_INTERVAL=86400 run "$SCRIPT"
  run cat "$BREW_LOG"
  [[ "$output" == *"brew autoupdate start 86400 --upgrade"* ]]
}
