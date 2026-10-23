#!/usr/bin/env bats

# config/lazygit/config.yml must keep lazygit's diffs going through delta, the
# pager .gitconfig sets for every diff, so the two never look different.

setup() {
  CONFIG="$BATS_TEST_DIRNAME/../config/lazygit/config.yml"
}

@test "lazygit pages diffs through delta" {
  run yq -r '.git.pagers[0].pager' "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == delta* ]]
}

@test "lazygit hands delta the terminal width" {
  run yq -r '.git.pagers[0].pager' "$CONFIG"
  [[ "$output" == *'--paging=never'* ]]
  [[ "$output" == *'--width={{columnWidth}}'* ]]
}
