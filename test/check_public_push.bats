#!/usr/bin/env bats

# Tests for bin/check_public_push.sh, the guard the `git` wrapper in .zshrc asks
# before letting a push through.
#
# The visibility answer comes from `gh`, so every case runs against a stub on
# PATH: it records that it was called (a guard that asks the network when it
# does not have to is a bug of its own) and answers what the case tells it to.
# bats gives the script no terminal, which is exactly the agent/CI path - the
# one that must refuse instead of defaulting to yes.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SCRIPT="$REPO_ROOT/bin/check_public_push.sh"
  TMP="$(fixture_tmpdir)"

  GH_STUB_CALLS="$TMP/gh-calls"
  : > "$GH_STUB_CALLS"
  export GH_STUB_CALLS
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'STUB'
#!/bin/sh
echo "$@" >> "$GH_STUB_CALLS"
case "${GH_STUB_VISIBILITY:-public}" in
  private) echo private ;;
  public)  echo public ;;
  *)       exit 1 ;;
esac
STUB
  chmod +x "$TMP/bin/gh"
  PATH="$TMP/bin:$PATH"
  export PATH

  REPO="$TMP/repo"
  git init -q -b main "$REPO"
  git -C "$REPO" remote add origin git@github.com:kimoto/thing.git
  cd "$REPO"
}

teardown() {
  rm -rf "$TMP"
}

gh_was_called() {
  [ -s "$GH_STUB_CALLS" ]
}

# --- what counts as a push -------------------------------------------------

@test "a command that is not a push is none of its business" {
  run "$SCRIPT" status --short
  [ "$status" -eq 0 ]
  ! gh_was_called
}

@test "global options in front of the subcommand still leave a push visible" {
  run "$SCRIPT" -C "$REPO" -c user.name=x push
  [ "$status" -eq 1 ]
  [[ "$output" == *"PUBLIC: kimoto/thing"* ]]
}

@test "a commit whose message merely contains the word push is not a push" {
  run "$SCRIPT" commit -m "push the release out"
  [ "$status" -eq 0 ]
  ! gh_was_called
}

# --- which remote is judged ------------------------------------------------

@test "with no remote named, the push is judged against origin" {
  run "$SCRIPT" push
  [ "$status" -eq 1 ]
  [[ "$output" == *"kimoto/thing"* ]]
}

@test "a URL given on the command line is judged, not origin" {
  run "$SCRIPT" push https://github.com/kimoto/other.git main
  [ "$status" -eq 1 ]
  [[ "$output" == *"kimoto/other"* ]]
}

@test "a remote that is not GitHub is left alone without asking gh" {
  git -C "$REPO" remote set-url origin "$TMP/bare.git"
  run "$SCRIPT" push
  [ "$status" -eq 0 ]
  ! gh_was_called
}

# --- the decision ----------------------------------------------------------

@test "a private repository is pushed to without a word" {
  GH_STUB_VISIBILITY=private run "$SCRIPT" push
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a public repository stops the push and says which one it is" {
  run "$SCRIPT" push origin main
  [ "$status" -eq 1 ]
  [[ "$output" == *"PUBLIC: kimoto/thing"* ]]
}

@test "a visibility gh cannot answer is treated as public, and says so" {
  GH_STUB_VISIBILITY=broken run "$SCRIPT" push
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNKNOWN visibility: kimoto/thing"* ]]
}

@test "the refusal offers no way around itself" {
  run "$SCRIPT" push
  [ "$status" -eq 1 ]
  [[ "$output" != *"PUBLIC_PUSH_OK"* ]]
}

@test "PUBLIC_PUSH_OK is the way through, and it asks gh nothing" {
  PUBLIC_PUSH_OK=1 run "$SCRIPT" push
  [ "$status" -eq 0 ]
  ! gh_was_called
}
