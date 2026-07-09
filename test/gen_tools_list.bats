#!/usr/bin/env bats

# Tests for bin/gen_tools_list.sh.
#
# The generator turns the `brew bundle dump --describe` Brewfiles into a grouped
# Markdown catalog. It must: attach each entry to the comment directly above it,
# link core-tap names to formulae.brew.sh (cask vs formula), leave third-party
# (slashed) names unlinked, drop taps, skip empty bundles, and — via --check —
# fail when the committed TOOLS.md no longer matches the Brewfiles.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/gen_tools_list.sh"
  TMP="$(mktemp -d)"
  cat >"$TMP/Brewfile.basic" <<'EOF'
# NOTE: Keep entries sorted A-Z within this file.
# Additional Homebrew tap
tap "some/tap"
# Modern, maintained replacement for ls
brew "eza"
# Cross-shell prompt for astronauts
brew "starship"
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "the repo's own TOOLS.md is in sync with the Brewfiles" {
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "renders each entry with its preceding description" {
  run "$SCRIPT" --stdout "$TMP/Brewfile.basic"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| [eza](https://formulae.brew.sh/formula/eza) | Modern, maintained replacement for ls |"* ]]
  [[ "$output" == *"| [starship](https://formulae.brew.sh/formula/starship) | Cross-shell prompt for astronauts |"* ]]
}

@test "drops tap entries from the catalog" {
  run "$SCRIPT" --stdout "$TMP/Brewfile.basic"
  [ "$status" -eq 0 ]
  [[ "$output" != *"some/tap"* ]]
}

@test "links casks to the cask path, not the formula path" {
  printf '# Terminal emulator\ncask "ghostty"\n' >"$TMP/Brewfile.macos"
  run "$SCRIPT" --stdout "$TMP/Brewfile.macos"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ghostty](https://formulae.brew.sh/cask/ghostty)"* ]]
}

@test "leaves third-party (slashed) formula names unlinked" {
  printf '# Homebrew formula\nbrew "owner/tap/thing"\n' >"$TMP/Brewfile.common"
  run "$SCRIPT" --stdout "$TMP/Brewfile.common"
  [ "$status" -eq 0 ]
  [[ "$output" == *'`owner/tap/thing`'* ]]
  [[ "$output" != *"formulae.brew.sh/formula/owner"* ]]
}

@test "skips a Brewfile with no brew/cask entries" {
  printf '# Linux-specific entries can be added here.\n' >"$TMP/Brewfile.linux"
  run "$SCRIPT" --stdout "$TMP/Brewfile.linux"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Brewfile.linux"* ]]
}

@test "a stray comment does not attach to an unrelated later entry" {
  printf '# orphan comment\n\nbrew "eza"\n' >"$TMP/Brewfile.orphan"
  run "$SCRIPT" --stdout "$TMP/Brewfile.orphan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| [eza](https://formulae.brew.sh/formula/eza) |  |"* ]]
}

@test "--check passes on a freshly written file and fails after it drifts" {
  export TOOLS_OUTPUT="$TMP/TOOLS.md"
  run "$SCRIPT" "$TMP/Brewfile.basic"
  [ "$status" -eq 0 ]
  run "$SCRIPT" --check "$TMP/Brewfile.basic"
  [ "$status" -eq 0 ]
  echo "hand edit" >>"$TMP/TOOLS.md"
  run "$SCRIPT" --check "$TMP/Brewfile.basic"
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of sync"* ]]
}
