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

@test "isolate_git_env turns off commit signing the fixture host may not be able to do" {
  # ~/.gitconfig sets commit.gpgsign = true and .gitconfig.default_user names a
  # signing key, and mklink.sh symlinks both into $HOME — so on any machine
  # without that secret key in its keyring (a fresh Linux box, a CI runner)
  # every fixture commit dies with "gpg failed to sign the data". Force-failing
  # both gpg.program and gpg.ssh.program covers a host on either signing
  # format — a Claude Code cloud container's ~/.gitconfig sets gpg.format=ssh
  # with a working gpg.ssh.program, which ignores gpg.program entirely.
  FIXTURE="$TMP/signing"
  git init -q -b main "$FIXTURE"
  git -C "$FIXTURE" config user.email t@t.test
  git -C "$FIXTURE" config user.name test
  git -C "$FIXTURE" config commit.gpgsign true
  # A host whose global gitconfig sets gpg.format=ssh with a working
  # gpg.ssh.program signs through that path, which outranks gpg.program —
  # so without pinning the format back here, the "red" check below would
  # succeed instead of failing via `false`.
  git -C "$FIXTURE" config gpg.format openpgp
  git -C "$FIXTURE" config gpg.program false
  git -C "$FIXTURE" config gpg.ssh.program false

  # Red without the helper: local config alone still forces a signature.
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
  run git -C "$FIXTURE" commit -q --allow-empty -m "feat: signed"
  [ "$status" -ne 0 ]

  isolate_git_env
  git -C "$FIXTURE" commit -q --allow-empty -m "feat: unsigned"
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

@test "fixture_tmpdir resolves a symlinked TMPDIR, as macOS always hands it one" {
  mkdir -p "$TMP/real"
  ln -s "$TMP/real" "$TMP/link"

  dir="$(TMPDIR="$TMP/link" fixture_tmpdir)"

  [ -d "$dir" ]
  # Returned unresolved, a fixture's own path and the one git reports for it
  # are two different strings for one directory.
  case "$dir" in "$TMP/link"/*) false ;; esac
  [ "$dir" = "$(cd "$dir" && pwd -P)" ]
}
