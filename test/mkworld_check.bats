#!/usr/bin/env bats

# MKWORLD_CHECK=1 must name the phase a machine is already at and leave the
# machine exactly as it found it. Only the phases below Homebrew are driven
# here: mkworld.sh looks for brew at fixed prefixes, so a stub on PATH cannot
# stand in for it on a machine that has the real one.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir "$HOME"
  # The real PATH minus zsh and brew, so the climb ends where the test says.
  BIN="$TMP/bin"
  mkdir "$BIN"
  local dir f b
  local IFS=:
  for dir in $PATH; do
    for f in "$dir"/*; do
      [ -e "$f" ] || continue
      b="${f##*/}"
      case "$b" in zsh|brew) continue ;; esac
      [ -e "$BIN/$b" ] || ln -s "$f" "$BIN/$b"
    done
  done
}

teardown() {
  rm -rf "$TMP"
}

snapshot() {
  (cd "$HOME" && find . | LC_ALL=C sort)
}

check() {
  run env -u CI PATH="$BIN" MKWORLD_CHECK=1 "$@" "$REPO_ROOT/bin/mkworld.sh"
}

@test "a check on an unlinked home reaches nothing, fails, and links nothing" {
  before="$(snapshot)"
  check
  [ "$status" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == "mkworld: reached nothing (stopped: ~/.bashrc is not linked to this checkout)" ]]
  [ "$(snapshot)" = "$before" ]
}

@test "a check on a linked home without zsh reaches minimal and changes nothing" {
  PATH="$BIN" "$REPO_ROOT/bin/mklink.sh" >/dev/null 2>&1
  before="$(snapshot)"
  check
  [ "$status" -eq 0 ]
  [[ "${lines[${#lines[@]}-1]}" == "mkworld: reached minimal (stopped: zsh not installed)" ]]
  [ "$(snapshot)" = "$before" ]
}

@test "a check below MKWORLD_EXPECT fails" {
  PATH="$BIN" "$REPO_ROOT/bin/mklink.sh" >/dev/null 2>&1
  check MKWORLD_EXPECT=platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"mkworld: expected to reach platform"* ]]
}

@test "a check notices one link that points elsewhere" {
  PATH="$BIN" "$REPO_ROOT/bin/mklink.sh" >/dev/null 2>&1
  rm "$HOME/.zshrc"
  : >"$HOME/.zshrc"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"~/.zshrc is not linked to this checkout"* ]]
}

@test "a check names the checkout it ran from, even when called through a link" {
  PATH="$BIN" "$REPO_ROOT/bin/mklink.sh" >/dev/null 2>&1
  # Resolved like the script resolves it: a checkout under a linked directory
  # is named by its real path.
  checkout=$(readlink -f "$REPO_ROOT")
  commit=$(git -C "$checkout" rev-parse --short HEAD)
  run env -u CI -u MKWORLD_TRACE PATH="$BIN" MKWORLD_CHECK=1 "$HOME/bin/mkworld.sh"
  [ "${lines[0]}" = "mkworld: checking $checkout at $commit" ]
}
