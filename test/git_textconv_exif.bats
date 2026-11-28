#!/usr/bin/env bats

# Tests for git's exif diff driver: config/git/attributes routes images to it,
# .gitconfig points it at bin/git_textconv_exif.sh.
#
# What these pin down: an image diff never kills `git diff` (exiftool is only in
# Brewfile.extra), and a change to the pixels alone still shows up as a change.

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
  git init -q "$REPO"
  printf 'one' >"$REPO/a.jpg"
  git -C "$REPO" add a.jpg
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m init
  printf 'two' >"$REPO/a.jpg"
}

teardown() {
  rm -rf "$TMP"
}

# A PATH holding only what git and the textconv need, so the real exiftool,
# installed or not, stays out of reach.
bare_path() {
  mkdir -p "$TMP/barebin"
  for t in git sh cksum; do ln -s "$(command -v "$t")" "$TMP/barebin/$t"; done
  printf '%s' "$TMP/barebin"
}

# Stand-in exiftool that reports the same metadata for every file, so only the
# checksum line can tell the two versions apart.
fake_exiftool() {
  mkdir -p "$TMP/fakebin"
  printf '#!/bin/sh\necho "ImageSize: 1x1"\n' >"$TMP/fakebin/exiftool"
  chmod +x "$TMP/fakebin/exiftool"
}

@test "an image diff without exiftool still succeeds and shows the change" {
  run env PATH="$(bare_path)" git -C "$REPO" --no-pager diff a.jpg
  [ "$status" -eq 0 ]
  [[ "$output" == *"exiftool not installed"* ]]
  [[ "$output" == *"-Checksum:"* ]]
  [[ "$output" == *"+Checksum:"* ]]
}

@test "an image diff shows exiftool's metadata" {
  fake_exiftool
  run env PATH="$TMP/fakebin:$(bare_path)" git -C "$REPO" --no-pager diff a.jpg
  [ "$status" -eq 0 ]
  [[ "$output" == *" ImageSize: 1x1"* ]]
}

@test "a pixel-only change is not hidden behind identical metadata" {
  fake_exiftool
  run env PATH="$TMP/fakebin:$(bare_path)" git -C "$REPO" --no-pager diff a.jpg
  [ "$status" -eq 0 ]
  [[ "$output" == *"+Checksum:"* ]]
}
