#!/usr/bin/env bats

# Behavioural tests for bin/setup_brew_auto_upgrade.sh, which installs the
# launchd agent that runs brew_auto_upgrade.sh daily. `uname`, `brew` and
# `launchctl` are stubs on PATH that record their calls; HOME is a temp dir, so
# no real Homebrew or launchd is touched.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  SCRIPT="$REPO_ROOT/bin/setup_brew_auto_upgrade.sh"
  export HOME="$TMP/home"
  AGENTS="$HOME/Library/LaunchAgents"
  PLIST="$AGENTS/local.dotfiles.brew-auto-upgrade.plist"
  CALLS="$TMP/calls.log"
  export CALLS
  : >"$CALLS"

  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  cat >"$STUB/uname" <<'STUBEOF'
#!/bin/bash
echo "${STUB_UNAME:-Darwin}"
STUBEOF
  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
echo "brew $*" >>"$CALLS"
if [ "$1" = "tap" ] && [ "$#" -eq 1 ] && [ "${STUB_DOMT4_TAPPED:-0}" = "1" ]; then
  echo "domt4/autoupdate"
fi
exit 0
STUBEOF
  # `launchctl print` succeeds only once something was bootstrapped.
  cat >"$STUB/launchctl" <<'STUBEOF'
#!/bin/bash
echo "launchctl $*" >>"$CALLS"
case "$1" in
  print) grep -q '^launchctl bootstrap' "$CALLS" ;;
esac
STUBEOF
  chmod +x "$STUB/uname" "$STUB/brew" "$STUB/launchctl"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "no-op on non-macOS" {
  STUB_UNAME=Linux run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping on non-macOS"* ]]
  [ ! -s "$CALLS" ]
}

@test "installs a daily calendar agent that runs this repo's upgrade script" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # grep, not plutil: CI runs these tests on Linux. plutil still catches a
  # malformed plist wherever it exists.
  if command -v plutil >/dev/null; then plutil -lint "$PLIST"; fi
  grep -q '<key>StartCalendarInterval</key>' "$PLIST"
  run grep -c '<key>StartInterval</key>' "$PLIST"
  [ "$output" = 0 ]
  grep -qF "<string>$REPO_ROOT/bin/brew_auto_upgrade.sh</string>" "$PLIST"
  grep -q "^launchctl bootstrap gui/$(id -u) $PLIST" "$CALLS"
  grep -q "^launchctl kickstart gui/$(id -u)/local.dotfiles.brew-auto-upgrade" "$CALLS"
}

@test "a rerun with the agent current changes nothing" {
  run "$SCRIPT"
  : >"$CALLS"
  echo "launchctl bootstrap (earlier)" >>"$CALLS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  run grep -c "kickstart" "$CALLS"
  [ "$output" = 0 ]
}

@test "takes out the homebrew/autoupdate agent and the untrusted domt4 tap" {
  mkdir -p "$AGENTS"
  echo old >"$AGENTS/com.github.domt4.homebrew-autoupdate.plist"
  STUB_DOMT4_TAPPED=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$AGENTS/com.github.domt4.homebrew-autoupdate.plist" ]
  grep -q "^launchctl bootout gui/$(id -u)/com.github.domt4.homebrew-autoupdate" "$CALLS"
  grep -q "^brew untap domt4/autoupdate" "$CALLS"
}

@test "leaves the taps alone when domt4/autoupdate is not present" {
  run "$SCRIPT"
  run grep -c "untap" "$CALLS"
  [ "$output" = 0 ]
}
