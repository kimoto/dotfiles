#!/usr/bin/env bats

# `temp` (.zshrc) cds into a fresh scratch directory under ~/tmp. Nothing in
# bin/ creates ~/tmp, so on a new machine it must make it itself rather than
# print a mktemp error and leave the shell where it was.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FAKE_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$FAKE_HOME"
}

run_temp() {
  run zsh -f -c "
    export HOME='$FAKE_HOME'
    export ZDOTDIR='$REPO_ROOT'
    export DOTFILES_NO_SYNC_CHECK=1
    export DOTFILES_NO_BREW_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    temp $1 && print -r -- \$PWD
  "
}

@test "temp creates ~/tmp when it does not exist yet" {
  run_temp foo
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "$FAKE_HOME"/tmp/*.foo.* ]]
  [ -d "${lines[-1]}" ]
}

@test "temp fails when the scratch directory cannot be made" {
  : >"$FAKE_HOME/tmp"
  run_temp foo
  [ "$status" -ne 0 ]
}
