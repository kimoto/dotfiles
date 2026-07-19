#!/usr/bin/env bats

# Behavioural tests for bin/brew_bundle_install.sh, the interactive (human-only)
# `brew bundle install` runner.
#
# The interactive flow itself needs a real terminal, which bats does not have —
# and that is exactly the point: the script must refuse to do anything without
# one, so an AI agent, CI, or a shell hook can never trigger installs. These
# tests cover that guard plus the pure log-parsing helpers, which are unit
# tested by sourcing the script (the source guard skips the main flow).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/brew_bundle_install.sh"
  TMP="$(mktemp -d)"

  # Fixture: representative failure output from a real `brew bundle install`.
  LOG="$TMP/bundle.log"
  cat >"$LOG" <<'EOF'
Fetching cleanshot, rectangle, stats
Using nikitabobko/tap
Error: Refusing to load cask nikitabobko/tap/aerospace from untrusted tap nikitabobko/tap.
Run `brew trust --cask nikitabobko/tap/aerospace` or `brew trust nikitabobko/tap` to trust it.
Upgrading rectangle
Warning: Reverting upgrade for Cask rectangle
Error: rectangle: It seems there is already an App at '/Applications/Rectangle.app'.
Installing aerospace has failed!
Upgrading rectangle has failed!
`brew bundle` failed! 2 Brewfile dependencies failed to install
EOF

  # Stub brew that records being called; the no-tty guard must fire before
  # brew is ever reached.
  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  cat >"$STUB/brew" <<STUBEOF
#!/bin/bash
touch "$TMP/brew_was_called"
exit 0
STUBEOF
  chmod +x "$STUB/brew"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "refuses to run without a terminal and never calls brew" {
  run "$SCRIPT" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal"* ]]
  [ ! -e "$TMP/brew_was_called" ]
}

@test "--help prints usage without needing a terminal" {
  run "$SCRIPT" --help </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ ! -e "$TMP/brew_was_called" ]
}

@test "rejects unknown arguments" {
  run "$SCRIPT" --bogus </dev/null
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/brew_was_called" ]
}

@test "parse_untrusted_taps extracts the tap name once" {
  run bash -c "source '$SCRIPT'; parse_untrusted_taps '$LOG'"
  [ "$status" -eq 0 ]
  [ "$output" = "nikitabobko/tap" ]
}

@test "parse_app_conflicts extracts the conflicting cask name" {
  run bash -c "source '$SCRIPT'; parse_app_conflicts '$LOG'"
  [ "$status" -eq 0 ]
  [ "$output" = "rectangle" ]
}

@test "parse_failed_deps lists every failed dependency" {
  run bash -c "source '$SCRIPT'; parse_failed_deps '$LOG'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "aerospace" ]
  [ "${lines[1]}" = "rectangle" ]
}

@test "failing_askpass resolves to an absolute executable path" {
  # sudo exec()s the askpass helper, so a bare builtin name like "false"
  # (what `command -v false` returns in bash) silently disables the guard
  # and sudo falls back to prompting on the tty mid-unattended-pass.
  run bash -c "source '$SCRIPT'; failing_askpass"
  [ "$status" -eq 0 ]
  [[ "$output" == /* ]]
  [ -x "$output" ]
}

@test "unattended pass sets SUDO_ASKPASS, the variable brew honours" {
  # Homebrew's env_config recognises plain SUDO_ASKPASS (not HOMEBREW_-prefixed)
  # and only passes sudo -A when that exact key is present.
  grep -q 'SUDO_ASKPASS=' "$SCRIPT"
  ! grep -q 'HOMEBREW_SUDO_ASKPASS' "$SCRIPT"
}

@test "parse helpers return nothing on a clean log" {
  local clean="$TMP/clean.log"
  echo "Using cleanshot" >"$clean"
  run bash -c "source '$SCRIPT'
    parse_untrusted_taps '$clean'; parse_app_conflicts '$clean'; parse_failed_deps '$clean'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
