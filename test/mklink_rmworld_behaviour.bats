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

# ~/.claude/rules/ is a conf.d: every .md under it loads into every session on
# this machine. Each source repo links its own subdirectory in, so rules from
# another repo can sit alongside ours. That only holds if mklink/rmworld touch
# nothing but our own entry — hence the "other sources" tests below. ~/.claude
# itself is never linked: it also holds runtime state (transcripts, sessions,
# plugin caches).

@test "mklink.sh links ~/.claude/rules/dotfiles to the repo's shared rules" {
  HOME="$HOME_SANDBOX" run sh "$MKLINK"
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.claude/rules/dotfiles" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/rules/dotfiles")" = "$REPO_ROOT/claudecode/rules" ]
}

@test "mklink.sh leaves rules linked in by another repo alone" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  ln -s /nonexistent-other-rules "$HOME_SANDBOX/.claude/rules/other"

  HOME="$HOME_SANDBOX" run sh "$MKLINK"   # re-running must not disturb it
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.claude/rules/other" ]
  [ "$(readlink "$HOME_SANDBOX/.claude/rules/other")" = /nonexistent-other-rules ]
}

@test "mklink.sh never touches a real ~/.claude/CLAUDE.md" {
  mkdir -p "$HOME_SANDBOX/.claude"
  echo "my own global instructions" >"$HOME_SANDBOX/.claude/CLAUDE.md"

  HOME="$HOME_SANDBOX" run sh "$MKLINK"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME_SANDBOX/.claude/CLAUDE.md" ]
  [ "$(cat "$HOME_SANDBOX/.claude/CLAUDE.md")" = "my own global instructions" ]
}

# ~/.claude/skills/ differs from rules/: skills installed by other tools live in
# the same directory, so ours are linked by name. Linking the directory itself
# would hide every one of them.

@test "mklink.sh links each of our skills into ~/.claude/skills by name" {
  HOME="$HOME_SANDBOX" run sh "$MKLINK"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME_SANDBOX/.claude/skills" ]
  [ -L "$HOME_SANDBOX/.claude/skills/session-resume" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/skills/session-resume")" \
      = "$REPO_ROOT/claudecode/skills/session-resume" ]
  [ -f "$HOME_SANDBOX/.claude/skills/session-resume/SKILL.md" ]
}

@test "mklink.sh leaves a skill installed by another tool alone" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  mkdir -p "$HOME_SANDBOX/.claude/skills/vendor-skill"
  echo vendor >"$HOME_SANDBOX/.claude/skills/vendor-skill/SKILL.md"

  HOME="$HOME_SANDBOX" run sh "$MKLINK"   # re-running must not disturb it
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME_SANDBOX/.claude/skills/vendor-skill/SKILL.md")" = vendor ]
}

@test "rmworld.sh unlinks our skills but leaves another tool's skill in place" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  mkdir -p "$HOME_SANDBOX/.claude/skills/vendor-skill"
  echo vendor >"$HOME_SANDBOX/.claude/skills/vendor-skill/SKILL.md"

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_SANDBOX/.claude/skills/session-resume" ]
  [ ! -e "$HOME_SANDBOX/.claude/skills/wrapup" ]
  [ "$(cat "$HOME_SANDBOX/.claude/skills/vendor-skill/SKILL.md")" = vendor ]
}

@test "rmworld.sh unlinks our rules but leaves another repo's rules in place" {
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  ln -s /nonexistent-other-rules "$HOME_SANDBOX/.claude/rules/other"

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_SANDBOX/.claude/rules/dotfiles" ]
  [ -L "$HOME_SANDBOX/.claude/rules/other" ]
}

@test "rmworld.sh removes the .zshrc wordcode cache, not just the symlink" {
  # .zshrc compiles itself to ~/.zshrc.zwc, and zsh loads that wordcode as the
  # startup file even when ~/.zshrc no longer exists — so leaving it behind
  # would keep the "removed" config loading in every new shell.
  HOME="$HOME_SANDBOX" sh "$MKLINK"
  printf 'compiled\n' >"$HOME_SANDBOX/.zshrc.zwc"
  printf 'partial\n' >"$HOME_SANDBOX/.zshrc.new.zwc"

  HOME="$HOME_SANDBOX" run sh "$RMWORLD"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_SANDBOX/.zshrc" ]
  [ ! -e "$HOME_SANDBOX/.zshrc.zwc" ]
  [ ! -e "$HOME_SANDBOX/.zshrc.new.zwc" ]
}
