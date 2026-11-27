#!/usr/bin/env bats

# Tests for bin/lint_osv.sh. The real scanner asks api.osv.dev, so these put a
# stub osv-scanner on PATH that records its arguments and exits with a chosen
# status: they check which lockfiles reach the scanner and that its verdict is
# passed through, not osv-scanner itself.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/repo/bin" "$TMP/stub"
  cp "$REPO_ROOT/bin/lint_osv.sh" "$REPO_ROOT/bin/lint_lib.sh" "$TMP/repo/bin/"
  git -C "$TMP/repo" init -q
  cat >"$TMP/stub/osv-scanner" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$OSV_ARGS"
exit "${OSV_STATUS:-0}"
STUB
  chmod +x "$TMP/stub/osv-scanner"
  export OSV_ARGS="$TMP/args"
  PATH="$TMP/stub:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

track() {
  local f
  for f in "$@"; do
    mkdir -p "$TMP/repo/$(dirname "$f")"
    : >"$TMP/repo/$f"
  done
  git -C "$TMP/repo" add -A
}

@test "passes every tracked uv.lock and requirements.txt to the scanner" {
  track .mise/locks/a/1.0/uv.lock hammerspoon/requirements.txt README.md
  run "$TMP/repo/bin/lint_osv.sh"
  [ "$status" -eq 0 ]
  run cat "$OSV_ARGS"
  [ "${lines[0]}" = scan ]
  [ "${lines[1]}" = source ]
  [[ "$output" == *$'-L\n.mise/locks/a/1.0/uv.lock'* ]]
  [[ "$output" == *$'-L\nhammerspoon/requirements.txt'* ]]
  [[ "$output" != *README.md* ]]
}

@test "an untracked lockfile is not scanned" {
  track hammerspoon/requirements.txt
  : >"$TMP/repo/uv.lock"
  run "$TMP/repo/bin/lint_osv.sh"
  [ "$status" -eq 0 ]
  run cat "$OSV_ARGS"
  [[ "$output" != *$'\nuv.lock'* ]]
}

@test "fails when the scanner reports a vulnerability" {
  track hammerspoon/requirements.txt
  OSV_STATUS=1 run "$TMP/repo/bin/lint_osv.sh"
  [ "$status" -eq 1 ]
}

@test "a repo with no lockfiles exits 0 without calling the scanner" {
  track README.md
  run "$TMP/repo/bin/lint_osv.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$OSV_ARGS" ]
}
