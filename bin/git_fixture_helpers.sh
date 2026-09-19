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
# git commands fall back to discovery from the cwd, and turn off commit signing
# for everything the suite runs.
#
# Signing: this repo's own .gitconfig sets commit.gpgsign = true and
# .gitconfig.default_user names a signing key, and mklink.sh symlinks both into
# $HOME. A fixture repo inherits that global config, so on any machine whose
# keyring lacks that secret key — a freshly bootstrapped Linux box, a CI runner
# — every `git commit` in the suite dies with "gpg failed to sign the data".
# Throwaway fixture commits gain nothing from a real signature, so the override
# goes here once instead of a `git config commit.gpgsign false` line each
# fixture has to remember. GIT_CONFIG_* is the right lever: unlike a per-repo
# `git config`, it outranks config files, so it also covers repos created by
# the script under test rather than by the fixture.
isolate_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX \
    GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE \
    GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
  export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
}

# fixture_tmpdir: a throwaway directory whose path is already resolved. macOS
# hands back /var/folders/... from mktemp -d while git and readlink report the
# /private/var/folders/... it points at, so a fixture that compares a path it
# built itself against one a command reported sees two strings for one
# directory. The template is spelled out because macOS mktemp ignores TMPDIR
# without one, which would leave the guard in the bats file unable to steer it.
fixture_tmpdir() {
  (cd "$(mktemp -d "${TMPDIR:-/tmp}/fixture.XXXXXXXX")" && pwd -P)
}
