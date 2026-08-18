#!/usr/bin/env bats

# Guards bin/git_fixture_helpers.sh, the isolation every fixture that builds a
# throwaway git repo depends on. Under lefthook's pre-commit (and `git bisect
# run`, `git rebase --exec`) the suite inherits GIT_DIR from the hook, and
# GIT_DIR outranks both `-C` and the cwd — so an un-isolated fixture commits
# into the developer's own checkout. Like the tmux e2e helpers, the second test
# keeps that from being re-learned one fixture at a time.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"

  # Stands in for the checkout the suite is being run from.
  OUTER="$TMP/outer"
  git init -q -b main "$OUTER"
  git -C "$OUTER" config user.email t@t.test
  git -C "$OUTER" config user.name test
  git -C "$OUTER" config commit.gpgsign false
  git -C "$OUTER" commit -q --allow-empty -m "chore: root"
}

teardown() {
  rm -rf "$TMP"
}

@test "isolate_git_env keeps a fixture's commits out of the inherited repo" {
  before="$(git -C "$OUTER" rev-parse HEAD)"

  export GIT_DIR="$OUTER/.git"
  isolate_git_env

  FIXTURE="$TMP/fixture"
  git init -q -b main "$FIXTURE"
  git -C "$FIXTURE" config user.email t@t.test
  git -C "$FIXTURE" config user.name test
  git -C "$FIXTURE" config commit.gpgsign false
  git -C "$FIXTURE" commit -q --allow-empty -m "feat: fixture"

  [ "$(git -C "$OUTER" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$FIXTURE" log --oneline | wc -l | tr -d ' ')" = "1" ]
}

@test "every fixture that runs git isolates the git env first" {
  cd "$REPO_ROOT"
  missing=""
  for f in test/*.bats; do
    grep -qE '(^|[^[:alnum:]_-])git ' "$f" || continue
    grep -q 'isolate_git_env' "$f" || missing="$missing $f"
  done
  [ -z "$missing" ] || echo "not isolated:$missing"
  [ -z "$missing" ]
}
