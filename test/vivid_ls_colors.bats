#!/usr/bin/env bats

# Tests for bin/vivid_ls_colors.sh, the wrapper that turns vivid's raw
# LS_COLORS value into an eval-able export so _evalcache can cache it
# (config/sheldon/plugins.toml, vivid-ls-colors inline plugin).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/vivid_ls_colors.sh"
  TMP="$(mktemp -d)"
  STUB="$TMP/stub"
  mkdir -p "$STUB"
}

teardown() {
  rm -rf "$TMP"
}

@test "wraps vivid's raw value in an eval-able export" {
  printf '#!/bin/sh\necho "di=1;34:*.txt=0;32"\n' >"$STUB/vivid"
  chmod +x "$STUB/vivid"
  run env PATH="$STUB:/usr/bin:/bin" "$SCRIPT"
  [ "$status" -eq 0 ]
  eval "$output"
  [ "$LS_COLORS" = 'di=1;34:*.txt=0;32' ]
}

@test "emits nothing and fails when vivid is absent (so _evalcache retries)" {
  # 127 = sh's command-not-found for the missing vivid binary.
  run -127 env PATH="$STUB:/usr/bin:/bin" "$SCRIPT"
  [[ "$output" != *"export LS_COLORS"* ]]
}
