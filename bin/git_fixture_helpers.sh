#!/bin/bash
# Shared helper for the bats tests that build a throwaway git repo. This file is
# *sourced*, not executed; source it from setup() before the first git call:
#
#   REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
#   # shellcheck source=/dev/null
#   . "$REPO_ROOT/bin/git_fixture_helpers.sh"
#   isolate_git_env
#
# Why: git exports GIT_DIR, GIT_INDEX_FILE and friends to the hooks it runs, so
# the whole suite inherits them whenever it runs from lefthook's pre-commit (and
# from `git bisect run` / `git rebase --exec`). GIT_DIR wins over both `-C` and
# the cwd, so a fixture's `git init "$TMP/repo"` re-inits the *caller's* gitdir
# and its commits land on the branch the developer is working on.

# isolate_git_env: drop every repo-scoped git variable git hands to a hook, so
# git commands fall back to discovery from the cwd.
isolate_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX \
    GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE \
    GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX
}
