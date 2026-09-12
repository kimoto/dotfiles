#!/usr/bin/env bats

# Tests for bin/lint_actions.sh, which verifies every GitHub Actions `uses:`
# is pinned to a full commit SHA (ratchet lint). The script always lints the
# workflows of the repo it lives in (BASE_DIR is derived from the script's own
# location), so the failure cases copy it into a throwaway git repo with a
# deliberately bad workflow — the real repo's workflows must stay green.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SCRIPT="$REPO_ROOT/bin/lint_actions.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Build a minimal git repo around a copy of the script, with one workflow
# whose checkout step uses the given ref. Sets permissions/persist-credentials
# so the fixture is zizmor-clean too — these tests are about ratchet, not it.
make_fixture_repo() {
  local ref="$1"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/.github/workflows"
  cp "$SCRIPT" "$TMP/repo/bin/"
  cat >"$TMP/repo/.github/workflows/ci.yml" <<EOF
on: push
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${ref}
        with:
          persist-credentials: false
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

# Same shape, but the workflow is correctly SHA-pinned and instead carries a
# mistake only actionlint sees — so a failure here cannot come from ratchet.
# Also zizmor-clean (permissions/persist-credentials set), same reasoning as
# make_fixture_repo above.
make_actionlint_fixture_repo() {
  local runner="$1"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/.github/workflows"
  cp "$SCRIPT" "$TMP/repo/bin/"
  cat >"$TMP/repo/.github/workflows/ci.yml" <<EOF
on: push
permissions:
  contents: read
jobs:
  build:
    runs-on: ${runner}
    steps:
      - uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5
        with:
          persist-credentials: false
      - run: echo hi
EOF
  git -C "$TMP/repo" init -q
  git -C "$TMP/repo" add -A
}

@test "rejects a workflow with an unknown runner label (actionlint, not ratchet)" {
  make_actionlint_fixture_repo "ubunt-latest"
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ubunt-latest"* ]]
}

@test "accepts the same workflow once the runner label is valid" {
  make_actionlint_fixture_repo "ubuntu-latest"
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -eq 0 ]
}

@test "the real repo's workflows are all SHA-pinned and actionlint-clean" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

# Same shape again, but missing permissions/persist-credentials entirely — a
# mistake only zizmor sees, so a failure here cannot come from ratchet or
# actionlint (both would accept this workflow).
make_zizmor_fixture_repo() {
  mkdir -p "$TMP/repo/bin" "$TMP/repo/.github/workflows"
  cp "$SCRIPT" "$TMP/repo/bin/"
  cat >"$TMP/repo/.github/workflows/ci.yml" <<EOF
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5
EOF
  git -C "$TMP/repo" init -q
  git -C "$TMP/repo" add -A
}

@test "rejects a workflow with no permissions block (zizmor, not ratchet/actionlint)" {
  make_zizmor_fixture_repo
  run "$TMP/repo/bin/lint_actions.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"excessive-permissions"* ]]
}
