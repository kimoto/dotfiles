#!/usr/bin/env bats

# Tests for bin/run_tests.sh's selection: which .bats files a set of staged
# paths reaches. RUN_TESTS_LIST=1 prints the selection without running it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/run_tests.sh"
  export RUN_TESTS_LIST=1
}

@test "no arguments selects the whole suite" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "test/" ]
}

@test "a staged .bats file selects itself" {
  run "$SCRIPT" test/protect_main.bats
  [ "$status" -eq 0 ]
  [ "$output" = "test/protect_main.bats" ]
}

@test "a staged script selects every .bats file that names it" {
  run "$SCRIPT" bin/mklink.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"test/mklink_rmworld_behaviour.bats"* ]]
  [[ "$output" == *"test/mklink_rmworld_sync.bats"* ]]
}

@test "a .bats file reached twice is listed once" {
  run "$SCRIPT" bin/protect_main.sh test/protect_main.bats
  [ "$status" -eq 0 ]
  [ "$(grep -c '^test/protect_main.bats$' <<<"$output")" -eq 1 ]
}

@test "paths no test covers select nothing and succeed" {
  run "$SCRIPT" README
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}
