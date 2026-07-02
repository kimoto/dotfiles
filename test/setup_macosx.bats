#!/usr/bin/env bats

# Behavioural tests for bin/setup_macosx.sh. Stubs `defaults`, `nvram`, and
# `sudo` so no real system state is touched; STUB_STARTUP_MUTE controls what
# `nvram StartupMute` reports back, letting us assert the sudo nvram write is
# skipped once it's already set.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/setup_macosx.sh"
  TMP="$(mktemp -d)"
  CMD_LOG="$TMP/cmd.log"
  export CMD_LOG

  STUB="$TMP/stubbin"
  mkdir -p "$STUB"

  cat >"$STUB/defaults" <<'STUBEOF'
#!/bin/bash
echo "defaults $*" >>"$CMD_LOG"
exit 0
STUBEOF

  cat >"$STUB/nvram" <<'STUBEOF'
#!/bin/bash
echo "nvram $*" >>"$CMD_LOG"
if [ "$#" -eq 1 ] && [ "$1" = "StartupMute" ]; then
  echo "StartupMute	${STUB_STARTUP_MUTE:-%00}"
fi
exit 0
STUBEOF

  cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
echo "sudo $*" >>"$CMD_LOG"
exec "$@"
STUBEOF

  chmod +x "$STUB/defaults" "$STUB/nvram" "$STUB/sudo"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "skips sudo nvram when StartupMute is already set" {
  STUB_STARTUP_MUTE='%01' run "$SCRIPT"
  [ "$status" -eq 0 ]
  run cat "$CMD_LOG"
  [[ "$output" != *"sudo nvram"* ]]
}

@test "runs sudo nvram when StartupMute is not yet set" {
  STUB_STARTUP_MUTE='%00' run "$SCRIPT"
  [ "$status" -eq 0 ]
  run cat "$CMD_LOG"
  [[ "$output" == *"sudo nvram StartupMute=%01"* ]]
}

@test "still applies the defaults writes regardless of StartupMute" {
  STUB_STARTUP_MUTE='%01' run "$SCRIPT"
  run cat "$CMD_LOG"
  [[ "$output" == *"defaults write com.apple.finder AppleShowAllFiles -bool YES"* ]]
}
