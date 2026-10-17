#!/usr/bin/env bats

# Tests for bin/ci_brew_cellar_cache.sh against a fake Homebrew prefix: save
# takes only the added formulae's Cellar directories and the links into them,
# and restore brings both back as they were.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/ci_brew_cellar_cache.sh"
  TMP="$(mktemp -d)"
  export BREW_PREFIX="$TMP/prefix"
  # Two formulae: eza (added by the run) and jq (the image's own).
  mkdir -p "$BREW_PREFIX/Cellar/eza/0.20.0/bin" "$BREW_PREFIX/Cellar/jq/1.8.0/bin"
  mkdir -p "$BREW_PREFIX/bin" "$BREW_PREFIX/opt" "$BREW_PREFIX/var/homebrew/linked" "$BREW_PREFIX/share/man/man1"
  echo eza >"$BREW_PREFIX/Cellar/eza/0.20.0/bin/eza"
  echo jq >"$BREW_PREFIX/Cellar/jq/1.8.0/bin/jq"
  ln -s ../Cellar/eza/0.20.0/bin/eza "$BREW_PREFIX/bin/eza"
  ln -s ../Cellar/jq/1.8.0/bin/jq "$BREW_PREFIX/bin/jq"
  ln -s ../Cellar/eza/0.20.0 "$BREW_PREFIX/opt/eza"
  ln -s "$BREW_PREFIX/Cellar/eza/0.20.0" "$BREW_PREFIX/var/homebrew/linked/eza"
  ln -s ../../../Cellar/eza/0.20.0/share/man/man1/eza.1 "$BREW_PREFIX/share/man/man1/eza.1"
  echo eza >"$TMP/added.txt"
}

teardown() {
  rm -rf "$TMP"
}

@test "save packs the added formula and its links, not the image's own" {
  run "$SCRIPT" save "$TMP/cellar.tar" "$TMP/added.txt"
  [ "$status" -eq 0 ]
  run tar -tf "$TMP/cellar.tar"
  [[ "$output" == *"Cellar/eza/0.20.0/bin/eza"* ]]
  [[ "$output" == *"bin/eza"* ]]
  [[ "$output" == *"opt/eza"* ]]
  [[ "$output" == *"var/homebrew/linked/eza"* ]]
  [[ "$output" == *"share/man/man1/eza.1"* ]]
  [[ "$output" != *"jq"* ]]
}

@test "restore brings the Cellar directory and the links back" {
  "$SCRIPT" save "$TMP/cellar.tar" "$TMP/added.txt"
  rm -rf "$BREW_PREFIX/Cellar/eza" "$BREW_PREFIX/bin/eza" "$BREW_PREFIX/opt/eza" \
    "$BREW_PREFIX/var/homebrew/linked/eza" "$BREW_PREFIX/share/man/man1/eza.1"
  run "$SCRIPT" restore "$TMP/cellar.tar"
  [ "$status" -eq 0 ]
  [ "$(cat "$BREW_PREFIX/bin/eza")" = eza ]
  [ "$(readlink "$BREW_PREFIX/opt/eza")" = ../Cellar/eza/0.20.0 ]
  [ -L "$BREW_PREFIX/var/homebrew/linked/eza" ]
}

@test "save fails when an added formula has no Cellar directory" {
  echo ghost >>"$TMP/added.txt"
  run "$SCRIPT" save "$TMP/cellar.tar" "$TMP/added.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
}

@test "save fails on an empty list" {
  : >"$TMP/added.txt"
  run "$SCRIPT" save "$TMP/cellar.tar" "$TMP/added.txt"
  [ "$status" -eq 1 ]
}

@test "restore fails on a missing archive" {
  run "$SCRIPT" restore "$TMP/none.tar"
  [ "$status" -eq 1 ]
}
