#!/usr/bin/env bats

# Tests for bin/lint_editorconfig.sh, which runs editorconfig-checker.
# editorconfig-checker resolves .editorconfig relative to each checked file,
# so the fixtures live in a temp dir with their own root .editorconfig — the
# repo's config (including .editorconfig-checker.json excludes/disables) is
# still what CI exercises via the no-argument test.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_editorconfig.sh"
  TMP="$(mktemp -d)"
  cat >"$TMP/.editorconfig" <<'EOF'
root = true

[*]
trim_trailing_whitespace = true
insert_final_newline = true
max_line_length = 120
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts a clean file" {
  printf 'clean line\n' >"$TMP/good.txt"
  run "$SCRIPT" "$TMP/good.txt"
  [ "$status" -eq 0 ]
}

@test "rejects trailing whitespace" {
  printf 'trailing whitespace   \n' >"$TMP/tw.txt"
  run "$SCRIPT" "$TMP/tw.txt"
  [ "$status" -ne 0 ]
}

@test "rejects a missing final newline" {
  printf 'no final newline' >"$TMP/nl.txt"
  run "$SCRIPT" "$TMP/nl.txt"
  [ "$status" -ne 0 ]
}

@test "rejects a line over max_line_length" {
  printf '%0.sx' {1..121} >"$TMP/long.txt"
  printf '\n' >>"$TMP/long.txt"
  run "$SCRIPT" "$TMP/long.txt"
  [ "$status" -ne 0 ]
}

@test "no arguments walks the whole repo and passes" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
