#!/usr/bin/env bats

# The Guide spoon's rules run in plain LuaJIT and its MCP server in plain python3, so CI checks both
# without a Mac or Hammerspoon. The drawing itself is only checked on a Mac.

setup() {
    cd "$BATS_TEST_DIRNAME/.." || exit 1
}

@test "guide logic: every rule holds" {
    run luajit test/guide_logic_test.lua
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "guide mcp: speaks MCP over stdio and reaches the spoon with its token" {
    run python3 -B -m unittest test/guide_mcp_test.py
    [ "$status" -eq 0 ]
}
