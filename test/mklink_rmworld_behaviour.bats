#!/usr/bin/env bats

# Behavioural tests for bin/mklink.sh and bin/rmworld.sh.
#
# These RUN the real scripts against a throwaway $HOME (mktemp), so the repo is
# never touched: both scripts cd into $HOME and operate on relative "./" paths,
# reading only BASE_DIR (the repo) as the link *source*. The companion
# mklink_rmworld_sync.bats only proves the two link LISTS match; this file
# proves the scripts actually behave — most importantly that mklink backs up a
# real ~/.config (the macOS-CI hazard noted in CLAUDE.md) and that rmworld never
# deletes a real file.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MKLINK="$REPO_ROOT/bin/mklink.sh"
  RMWORLD="$REPO_ROOT/bin/rmworld.sh"
  HOME_SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME_SANDBOX"
}

@test "mklink.sh links dotfiles in HOME back to the repo" {
  HOME="$HOME_SANDBOX" run sh "$MKLINK"
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.zshrc" ]
  [ -L "$HOME_SANDBOX/.config" ]
  [ -L "$HOME_SANDBOX/bin" ]
  # The links must resolve to this repo's real files, not dangle.
  [ "$(readlink -f "$HOME_SANDBOX/.zshrc")" = "$REPO_ROOT/.zshrc" ]
  [ "$(readlink -f "$HOME_SANDBOX/.config")" = "$REPO_ROOT/config" ]
  [ "$(readlink -f "$HOME_SANDBOX/bin")" = "$REPO_ROOT/bin" ]
}

@test "mklink.sh backs up a real ~/.config before replacing it with a symlink" {
  mkdir -p "$HOME_SANDBOX/.config"
  echo keep >"$HOME_SANDBOX/.config/sentinel"

  HOME="$HOME_SANDBOX" run sh "$MKLINK"
  [ "$status" -eq 0 ]

  # .config is now a symlink into the repo...
  [ -L "$HOME_SANDBOX/.config" ]
  [ "$(readlink -f "$HOME_SANDBOX/.config")" = "$REPO_ROOT/config" ]
  # ...and the original real dir was preserved in a timestamped backup.
  backup=$(find "$HOME_SANDBOX" -maxdepth 1 -name '.config.bak.*' -type d)
  [ -n "$backup" ]
  [ "$(cat "$backup/sentinel")" = keep ]
}

@test "mklink.sh does not back up when ~/.config is already a symlink" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"          # first run creates the symlink
  HOME="$HOME_SANDBOX" run sh "$MKLINK"      # second run must be a no-op for backups
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.config" ]
  run find "$HOME_SANDBOX" -maxdepth 1 -name '.config.bak.*'
  [ -z "$output" ]
}

@test "rmworld.sh removes the symlinks mklink.sh created" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  [ -L "$HOME_SANDBOX/.zshrc" ]

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_SANDBOX/.zshrc" ]
  [ ! -e "$HOME_SANDBOX/.config" ]
  [ ! -e "$HOME_SANDBOX/bin" ]
}

@test "rmworld.sh never deletes a real file standing in for a linked dotfile" {
  echo "my own zshrc" >"$HOME_SANDBOX/.zshrc"   # a REAL file, not a symlink

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ -f "$HOME_SANDBOX/.zshrc" ]
  [ ! -L "$HOME_SANDBOX/.zshrc" ]
  [ "$(cat "$HOME_SANDBOX/.zshrc")" = "my own zshrc" ]
}

@test "rmworld.sh leaves a real ~/.config directory untouched" {
  mkdir -p "$HOME_SANDBOX/.config"
  echo keep >"$HOME_SANDBOX/.config/sentinel"

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ -d "$HOME_SANDBOX/.config" ]
  [ ! -L "$HOME_SANDBOX/.config" ]
  [ "$(cat "$HOME_SANDBOX/.config/sentinel")" = keep ]
}
