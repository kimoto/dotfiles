#!/usr/bin/env bats

# Tests for bin/lint_actions.sh, which verifies every GitHub Actions `uses:`
# is pinned to a full commit SHA (ratchet lint). The script always lints the
# workflows of the repo it lives in (BASE_DIR is derived from the script's own
# location), so the failure cases copy it into a throwaway git repo with a
# deliberately bad workflow — the real repo's workflows must stay green.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_actions.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Build a minimal git repo around a copy of the script, with one workflow
# whose checkout step uses the given ref.
make_fixture_repo() {
  local ref="$1"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/.github/workflows"
  cp "$SCRIPT" "$TMP/repo/bin/"
  cat >"$TMP/repo/.github/workflows/ci.yml" <<EOF
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${ref}
EOF
  git -C "$TMP/repo" init -q
  git -C "$TMP/repo" add -A
}

@test "rejects a workflow pinned to a mutable tag" {
  make_fixture_repo "v4"
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -ne 0 ]
}

@test "accepts a workflow pinned to a full commit SHA" {
  make_fixture_repo "93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5"
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -eq 0 ]
}

@test "a repo with no workflows exits 0" {
  mkdir -p "$TMP/repo/bin"
  cp "$SCRIPT" "$TMP/repo/bin/"
  git -C "$TMP/repo" init -q
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -eq 0 ]
}

@test "the real repo's workflows are all SHA-pinned" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}
