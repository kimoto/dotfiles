#!/usr/bin/env bats

# Tests for bin/lint_yaml.sh, which style-lints YAML with yamllint against the
# repo's .yamllint.yml. The script always resolves that config from its own
# location, so fixtures can live anywhere and still be judged by the real rules.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_yaml.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a clean YAML file" {
  printf 'key: value\nlist:\n  - one\n  - two\n' >"$TMP/ok.yml"
  run "$SCRIPT" "$TMP/ok.yml"
  [ "$status" -eq 0 ]
}

@test "rejects trailing whitespace" {
  printf 'key: value   \n' >"$TMP/bad.yml"
  run "$SCRIPT" "$TMP/bad.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"trailing-spaces"* ]]
}

@test "rejects a line longer than the .editorconfig limit" {
  printf 'key: %s\n' "$(printf 'x%.0s' {1..130})" >"$TMP/long.yml"
  run "$SCRIPT" "$TMP/long.yml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"line-length"* ]]
}

@test "keeps the relaxations the repo's own conventions need" {
  # A one-space pin comment (ratchet's format), a workflow-style truthy `on:`
  # key, and no document-start marker: all three are default yamllint errors
  # and all three are how this repo already writes YAML.
  printf 'on: push\njobs:\n  build:\n    steps:\n      - uses: a/b@sha # v5\n' >"$TMP/conv.yml"
  run "$SCRIPT" "$TMP/conv.yml"
  [ "$status" -eq 0 ]
}

@test "fails the batch if any one file is broken" {
  printf 'key: value\n' >"$TMP/ok.yml"
  printf 'key: value   \n' >"$TMP/bad.yml"
  run "$SCRIPT" "$TMP/ok.yml" "$TMP/bad.yml"
  [ "$status" -ne 0 ]
}

@test "skips arguments that no longer exist (staged deletion)" {
  printf 'key: value\n' >"$TMP/ok.yml"
  run "$SCRIPT" "$TMP/ok.yml" "$TMP/deleted.yml"
  [ "$status" -eq 0 ]
}

@test "no arguments and a clean repo exits 0 (the repo's own YAML passes)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
