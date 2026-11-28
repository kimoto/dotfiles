#!/usr/bin/env bats

# Tests for bin/check_agents_size.sh: it rejects an AGENTS.md over the byte cap
# and accepts one under it; with no argument it checks the repo's own file.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_agents_size.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "the repo's own AGENTS.md is under the cap" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "accepts a file under the cap" {
  head -c 100 /dev/zero >"$TMP/AGENTS.md"
  AGENTS_MD_MAX_BYTES=100 run "$SCRIPT" "$TMP/AGENTS.md"
  [ "$status" -eq 0 ]
}

@test "rejects a file over the cap and says by how much" {
  head -c 101 /dev/zero >"$TMP/AGENTS.md"
  AGENTS_MD_MAX_BYTES=100 run "$SCRIPT" "$TMP/AGENTS.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"101 bytes"* ]]
}
