#!/usr/bin/env bats

# Tests for the decision logic in hammerspoon/displays.lua: which monitor set
# is connected, and whether a settled screen change restores, saves or leaves
# the arrangement alone. Runs under luajit, with no Mac and no monitors — the
# hs.* side is only exercised on a real machine.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# Evaluate a Lua expression with the module loaded as `d` and print its value.
lua_eval() {
  luajit -e "package.path = '$REPO_ROOT/hammerspoon/?.lua;' .. package.path
local d = require('displays')
print($1)"
}

@test "set key ignores which port each monitor is on" {
  run lua_eval 'd.setKey({ "LG HDR 4K", "Built-in" }) == d.setKey({ "Built-in", "LG HDR 4K" })'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "set key keeps two identical monitors distinct from one" {
  run lua_eval 'd.setKey({ "DELL U2720Q", "DELL U2720Q" }) ~= d.setKey({ "DELL U2720Q" })'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "plugging in a known set restores its saved arrangement" {
  run lua_eval 'd.decide("A", "A + B", "saved", "macos-default")'
  [ "$output" = "apply" ]
}

@test "plugging in an unknown set saves what macOS chose" {
  run lua_eval 'd.decide("A", "A + B", nil, "macos-default")'
  [ "$output" = "save" ]
}

@test "rearranging the same set saves the new arrangement" {
  run lua_eval 'd.decide("A + B", "A + B", "old", "new")'
  [ "$output" = "save" ]
}

@test "the change a restore itself causes saves nothing" {
  run lua_eval 'd.decide("A + B", "A + B", "saved", "saved")'
  [ "$output" = "none" ]
}

@test "a known set already in its saved arrangement is left alone" {
  run lua_eval 'd.decide("A", "A + B", "saved", "saved")'
  [ "$output" = "none" ]
}
