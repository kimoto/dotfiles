#!/usr/bin/env bats

# Tests for git's mergiraf merge driver: config/git/attributes routes source
# files to it, .gitconfig points it at bin/git_merge_mergiraf.sh.
#
# What these pin down: without mergiraf (it is only in Brewfile.extra) a merge
# behaves as plain git's would, and with it the driver hands mergiraf the merge.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"
  # The layout mklink.sh builds: ~/bin and ~/.config point into this repo.
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  ln -s "$REPO_ROOT/bin" "$HOME/bin"
  export GIT_CONFIG_GLOBAL="$REPO_ROOT/.gitconfig"
  export XDG_CONFIG_HOME="$REPO_ROOT/config"

  REPO="$TMP/repo"
  git init -q -b main "$REPO"
  printf 'first = 1\nf(a, b)\nlast = 1\n' >"$REPO/m.py"
  commit_all init
}

teardown() {
  rm -rf "$TMP"
}

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m "$1"
}

# Two branches off main, each writing its own version of m.py, with `side`
# checked out last so the merge brings `side` into `main`.
branches() {
  git -C "$REPO" switch -q -c side
  printf '%b' "$2" >"$REPO/m.py"
  commit_all side
  git -C "$REPO" switch -q main
  printf '%b' "$1" >"$REPO/m.py"
  commit_all main
}

merge() {
  git -C "$REPO" -c user.name=t -c user.email=t@example.com merge -q --no-edit side
}

# A PATH holding only what git and the driver need, so the real mergiraf,
# installed or not, stays out of reach.
bare_path() {
  mkdir -p "$TMP/barebin"
  for t in git sh; do ln -s "$(command -v "$t")" "$TMP/barebin/$t"; done
  printf '%s' "$TMP/barebin"
}

@test "without mergiraf, edits to separate lines merge cleanly" {
  branches 'first = 2\nf(a, b)\nlast = 1\n' 'first = 1\nf(a, b)\nlast = 2\n'
  PATH="$(bare_path)" run merge
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/m.py")" = "$(printf 'first = 2\nf(a, b)\nlast = 2')" ]
}

@test "without mergiraf, a same-line conflict stops the merge with zdiff3 markers" {
  branches 'first = 1\nf(a2, b)\nlast = 1\n' 'first = 1\nf(a, b2)\nlast = 1\n'
  PATH="$(bare_path)" run merge
  [ "$status" -ne 0 ]
  grep -q '^<<<<<<< ' "$REPO/m.py"
  grep -q '^||||||| ' "$REPO/m.py"
}

@test "with mergiraf on PATH, the driver hands it the merge" {
  branches 'first = 1\nf(a2, b)\nlast = 1\n' 'first = 1\nf(a, b2)\nlast = 1\n'
  # Stand-in that records how it was called and writes a fixed result into the
  # current version's file (its 3rd argument after `merge --git`).
  mkdir -p "$TMP/fakebin"
  cat >"$TMP/fakebin/mergiraf" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >"$TMP/args"
printf 'merged\n' >"\$4"
STUB
  chmod +x "$TMP/fakebin/mergiraf"
  PATH="$TMP/fakebin:$(bare_path)" run merge
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/m.py")" = merged ]
  [[ "$(cat "$TMP/args")" == "merge --git "*" -p m.py "* ]]
}

@test "real mergiraf merges edits to different arguments of one call" {
  command -v mergiraf >/dev/null || skip "mergiraf not installed"
  branches 'first = 1\nf(a2, b)\nlast = 1\n' 'first = 1\nf(a, b2)\nlast = 1\n'
  run merge
  [ "$status" -eq 0 ]
  grep -q '^f(a2, b2)$' "$REPO/m.py"
}
