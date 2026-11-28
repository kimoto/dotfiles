#!/usr/bin/env bats

# Tests for .claude/hooks/git-leftovers-reminder.sh, the Stop hook that tells the
# agent what it has not pushed yet. A branch that was never pushed has no
# upstream, and it is the work easiest to lose, so the hook must still count its
# commits against the default branch rather than report nothing.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  HOOK="$REPO_ROOT/.claude/hooks/git-leftovers-reminder.sh"
  TMP="$(fixture_tmpdir)"
  # The hook keeps its last report under $HOME; keep it out of the real one.
  export HOME="$TMP/home"
  mkdir -p "$HOME"

  git init -q --bare -b main "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/repo" 2>/dev/null
  cd "$TMP/repo"
  git config user.email t@example.com
  git config user.name t
  git commit -q --allow-empty -m "chore: root"
  git push -q origin main
  git remote set-head origin main
  git switch -q -c feature
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "counts commits on a branch that was never pushed" {
  git commit -q --allow-empty -m "feat: local only"
  run "$HOOK" <<<'{"session_id":"s1"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 uncommitted, 0 untracked, 1 unpushed"* ]]
}

@test "stays silent on a never-pushed branch with nothing new" {
  run "$HOOK" <<<'{"session_id":"s1"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
