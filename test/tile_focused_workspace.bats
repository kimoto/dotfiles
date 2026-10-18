#!/usr/bin/env bats

# Tests for bin/tile-focused-workspace.sh, run from AeroSpace's service mode.
#
# A fake `aerospace` on PATH records each call, so the tests see which layout
# reached which window without a running window manager.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/tile-focused-workspace.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/aerospace" <<'EOF'
#!/bin/sh
echo "$*" >>"$CALLS"
if [ "$1" = list-windows ]; then
  printf '11\n22\n'
fi
EOF
  chmod +x "$TMP/bin/aerospace"
  export CALLS="$TMP/calls"
  PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "applies the layout to every window in the focused workspace" {
  run "$SCRIPT" tiling
  [ "$status" -eq 0 ]
  grep -qx 'layout tiling --window-id 11' "$CALLS"
  grep -qx 'layout tiling --window-id 22' "$CALLS"
}

@test "refuses a missing layout before touching any window" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
  [ ! -e "$CALLS" ]
}

@test "refuses a layout other than tiling or floating" {
  run "$SCRIPT" tiles
  [ "$status" -eq 2 ]
  [ ! -e "$CALLS" ]
}
