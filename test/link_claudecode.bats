#!/usr/bin/env bats

# Behavioural tests for bin/link_claudecode.sh — the Claude Code half of
# mklink.sh, split out so a cloud environment's setup script can run it alone.
#
# A cloud session's $HOME is not ours: git identity, credentials and shell
# config are provisioned by the platform. So the invariant that matters most
# here is the negative one — this script touches nothing outside ~/.claude.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINK="$REPO_ROOT/bin/link_claudecode.sh"
  HOME_SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME_SANDBOX"
}

@test "links the rules directory as our own conf.d entry" {
  HOME="$HOME_SANDBOX" run sh "$LINK"
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.claude/rules/dotfiles" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/rules/dotfiles")" = "$REPO_ROOT/claudecode/rules" ]
}

@test "links every skill in the repo, one entry per skill" {
  HOME="$HOME_SANDBOX" run sh "$LINK"
  [ "$status" -eq 0 ]
  for src in "$REPO_ROOT"/claudecode/skills/*/; do
    name=$(basename "$src")
    [ -L "$HOME_SANDBOX/.claude/skills/$name" ]
    [ "$(readlink -f "$HOME_SANDBOX/.claude/skills/$name")" = "$REPO_ROOT/claudecode/skills/$name" ]
  done
}

@test "touches nothing outside ~/.claude" {
  # The hazard this split exists to avoid: mklink.sh also links ~/.gitconfig,
  # ~/.config, ~/bin and ~/.zshrc. In a cloud session those are the platform's
  # — clobbering ~/.gitconfig alone would break every commit and push.
  HOME="$HOME_SANDBOX" run sh "$LINK"
  [ "$status" -eq 0 ]
  run find "$HOME_SANDBOX" -maxdepth 1 -mindepth 1 ! -name .claude
  [ -z "$output" ]
}

@test "leaves another tool's skill alone" {
  # ~/.claude/skills is shared with skills other tools install, which is why
  # each of ours is linked by name and the directory itself never is.
  mkdir -p "$HOME_SANDBOX/.claude/skills/someone-elses"
  echo keep >"$HOME_SANDBOX/.claude/skills/someone-elses/SKILL.md"

  HOME="$HOME_SANDBOX" run sh "$LINK"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME_SANDBOX/.claude/skills" ]
  [ "$(cat "$HOME_SANDBOX/.claude/skills/someone-elses/SKILL.md")" = keep ]
}

@test "is idempotent" {
  HOME="$HOME_SANDBOX" sh "$LINK"
  HOME="$HOME_SANDBOX" run sh "$LINK"
  [ "$status" -eq 0 ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/rules/dotfiles")" = "$REPO_ROOT/claudecode/rules" ]
}
