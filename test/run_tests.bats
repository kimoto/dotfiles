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

# A fake bats records how it was called, next to a fake GNU parallel when the
# test wants one. The real one would run the suite from inside the suite.
fake_tools() {
  BIN="$(mktemp -d)"
  printf '#!/bin/sh\necho "$*" >"%s/args"\n' "$BIN" >"$BIN/bats"
  chmod +x "$BIN/bats"
  if [ "${1:-}" = parallel ]; then
    printf '#!/bin/sh\n' >"$BIN/parallel"
    chmod +x "$BIN/parallel"
  fi
}

# PATH with GNU parallel taken out. A directory that holds it also holds
# bash and the rest, so it is mirrored without parallel instead of dropped.
path_without_parallel() {
  local d out="" n=0
  local IFS=:
  for d in $PATH; do
    if [ -x "$d/parallel" ]; then
      n=$((n + 1))
      mkdir -p "$BIN/mirror$n"
      ln -s "$d"/* "$BIN/mirror$n/"
      rm "$BIN/mirror$n/parallel"
      d="$BIN/mirror$n"
    fi
    out="$out${out:+:}$d"
  done
  printf '%s' "$out"
}

@test "the whole suite runs its files in parallel when GNU parallel is there" {
  [ "$(getconf _NPROCESSORS_ONLN)" -gt 1 ] || skip "one CPU"
  fake_tools parallel
  RUN_TESTS_LIST= PATH="$BIN:$PATH" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(cat "$BIN/args")" == "--jobs "*" --no-parallelize-within-files "*"test/" ]]
  rm -rf "$BIN"
}

@test "without GNU parallel the suite runs one file at a time" {
  fake_tools
  RUN_TESTS_LIST= PATH="$BIN:$(path_without_parallel)" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$BIN/args")" = "--print-output-on-failure test/" ]
  rm -rf "$BIN"
}

@test "a single file is not worth starting GNU parallel for" {
  fake_tools parallel
  RUN_TESTS_LIST= PATH="$BIN:$PATH" run "$SCRIPT" test/protect_main.bats
  [ "$status" -eq 0 ]
  [ "$(cat "$BIN/args")" = "--print-output-on-failure test/protect_main.bats" ]
  rm -rf "$BIN"
}
