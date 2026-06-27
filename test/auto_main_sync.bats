#!/usr/bin/env bats

# Behavioural tests for .claude/hooks/auto-main-sync.sh, the SessionEnd hook that
# returns a clean feature branch to main once its PR has merged.
#
# The hook inspects $CLAUDE_PROJECT_DIR, talks to `gh`, and mutates the checkout
# (switch/pull/branch -d). Each test runs the real hook against a throwaway git
# repo wired to a local bare "remote" (no network) and a stub `gh` on PATH whose
# answer is driven by $FAKE_PR_OUTPUT. Hook output goes to stdout, folded into
# $output by bats.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/auto-main-sync.sh"
  TMP="$(mktemp -d)"

  # Stub gh: prints $FAKE_PR_OUTPUT, or fails (no PR) when it is empty.
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/gh" <<'EOF'
#!/bin/bash
[ -n "${FAKE_PR_OUTPUT:-}" ] || exit 1
echo "$FAKE_PR_OUTPUT"
EOF
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"

  # A bare remote with main at commit A, plus a feature branch carrying one
  # commit; the remote's main is advanced to that commit to mimic a merged PR.
  REPO="$TMP/repo"
  git init -q --bare "$TMP/remote.git"
  git -c init.defaultBranch=main clone -q "$TMP/remote.git" "$REPO"
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name "Test"
  echo a >"$REPO/file.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: seed"
  git -C "$REPO" branch -M main          # empty-clone default may not be 'main'
  git -C "$REPO" push -q -u origin main

  export CLAUDE_PROJECT_DIR="$REPO"
}

teardown() {
  rm -rf "$TMP"
}

# Put $REPO on a clean feature branch whose work is already on the remote's main
# (the merged-PR state): local main stays behind, so a later pull fast-forwards.
on_merged_feature_branch() {
  git -C "$REPO" switch -q -c feature
  echo work >>"$REPO/file.txt"
  git -C "$REPO" commit -qam "feat: work"
  git -C "$REPO" push -q -u origin feature
  git -C "$REPO" push -q origin feature:main   # advance remote main -> merged
}

@test "merged PR on a clean tree: switches to main, pulls, deletes the branch" {
  on_merged_feature_branch
  FAKE_PR_OUTPUT="#1 MERGED" run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(git -C "$REPO" branch --show-current)" = "main" ]
  git -C "$REPO" merge-base --is-ancestor HEAD origin/main   # main pulled up to the merge
  run git -C "$REPO" rev-parse --verify feature              # branch deleted
  [ "$status" -ne 0 ]
}

@test "merged PR but dirty tree: only reminds, never touches the checkout" {
  on_merged_feature_branch
  echo dirty >>"$REPO/file.txt"
  FAKE_PR_OUTPUT="#1 MERGED" run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty"* ]]
  [ "$(git -C "$REPO" branch --show-current)" = "feature" ]
}

@test "open PR: reminds and stays on the branch" {
  on_merged_feature_branch
  FAKE_PR_OUTPUT="#1 OPEN" run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"open"* ]]
  [ "$(git -C "$REPO" branch --show-current)" = "feature" ]
}

@test "already on main: silent no-op" {
  FAKE_PR_OUTPUT="#1 MERGED" run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no PR for the branch: silent" {
  git -C "$REPO" switch -q -c feature
  FAKE_PR_OUTPUT="" run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(git -C "$REPO" branch --show-current)" = "feature" ]
}
