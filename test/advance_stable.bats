#!/usr/bin/env bats

# Tests for ci/advance_stable.sh with a stub `gh` that records every call and
# answers the ref lookup and the compare from environment variables.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/ci/advance_stable.sh"
  TMP="$(mktemp -d)"
  export GH_LOG="$TMP/gh.log"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
  *"git/ref/heads/stable"*) [ "${STUB_STABLE_EXISTS:-1}" = 1 ] ;;
  *"/compare/"*) echo "$STUB_COMPARE" ;;
  *) : ;;
esac
STUB
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"
  export GITHUB_REPOSITORY=owner/repo
}

teardown() {
  rm -rf "$TMP"
}

@test "creates stable at the commit when it does not exist yet" {
  STUB_STABLE_EXISTS=0 run "$SCRIPT" abc123
  [ "$status" -eq 0 ]
  grep -q -- "-X POST repos/owner/repo/git/refs -f ref=refs/heads/stable -f sha=abc123" "$GH_LOG"
}

@test "fast-forwards stable when the commit descends from it" {
  STUB_COMPARE=ahead run "$SCRIPT" abc123
  [ "$status" -eq 0 ]
  grep -q -- "-X PATCH repos/owner/repo/git/refs/heads/stable -f sha=abc123 -F force=false" "$GH_LOG"
}

@test "leaves stable alone when a newer run already moved it past the commit" {
  STUB_COMPARE=behind run "$SCRIPT" abc123
  [ "$status" -eq 0 ]
  ! grep -q -- "-X PATCH" "$GH_LOG"
}

@test "leaves stable alone when it already points at the commit" {
  STUB_COMPARE=identical run "$SCRIPT" abc123
  [ "$status" -eq 0 ]
  ! grep -q -- "-X PATCH" "$GH_LOG"
}

@test "refuses to move stable across a divergence" {
  STUB_COMPARE=diverged run "$SCRIPT" abc123
  [ "$status" -ne 0 ]
  ! grep -q -- "-X PATCH" "$GH_LOG"
}

@test "fails without a commit to advance to" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
