#!/usr/bin/env bats

# The Curtain spoon's rules run in plain LuaJIT, so CI checks them without a Mac or Hammerspoon.

setup() {
    cd "$BATS_TEST_DIRNAME/.." || exit 1
}

@test "curtain logic: every rule holds" {
    run luajit test/curtain_logic_test.lua
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
