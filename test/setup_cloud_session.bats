#!/usr/bin/env bats

# Behavioural tests for bin/setup_cloud_session.sh.
#
# Like mklink_rmworld_behaviour.bats these RUN the real script against a
# throwaway $HOME, because the thing worth proving is what it does to a
# container: that it links the ~/.claude entries, that it links *only* those
# (a cloud session that acquired .zshrc or .gitconfig is the failure this
# script exists to avoid), and that it still exits 0 when a link could not be
# made — the Setup script field fails the whole session on a non-zero exit, so
# the MISS line is the only signal left and has to be there.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SETUP="$REPO_ROOT/bin/setup_cloud_session.sh"
  HOME_SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME_SANDBOX"
}

@test "links the rules, the cloud scope rule, and every skill" {
  HOME="$HOME_SANDBOX" run "$SETUP"
  [ "$status" -eq 0 ]

  [ -L "$HOME_SANDBOX/.claude/rules/dotfiles" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/rules/dotfiles")" \
      = "$REPO_ROOT/claudecode/rules" ]
  [ -f "$HOME_SANDBOX/.claude/rules/dotfiles/writing.md" ]

  [ -L "$HOME_SANDBOX/.claude/rules/dotfiles-cloud" ]
  [ -f "$HOME_SANDBOX/.claude/rules/dotfiles-cloud/scope.md" ]

  # Every skill in the repo, not a list repeated here: a skill added upstream
  # must arrive without this test being edited, which is the property the walk
  # buys over mklink.sh's named entries.
  for skill in "$REPO_ROOT"/claudecode/skills/*/; do
    name="$(basename "$skill")"
    [ -L "$HOME_SANDBOX/.claude/skills/$name" ]
    [ -f "$HOME_SANDBOX/.claude/skills/$name/SKILL.md" ]
  done
}

@test "links nothing outside ~/.claude" {
  HOME="$HOME_SANDBOX" run "$SETUP"
  [ "$status" -eq 0 ]

  # The two that break a cloud session rather than merely adding to it.
  [ ! -e "$HOME_SANDBOX/.zshrc" ]
  [ ! -e "$HOME_SANDBOX/.gitconfig" ]

  # And nothing else either: .claude is the only entry it may create.
  run find "$HOME_SANDBOX" -mindepth 1 -maxdepth 1 -not -name .claude
  [ -z "$output" ]
}

@test "leaves a skill directory it did not create alone" {
  name="$(basename "$(find "$REPO_ROOT/claudecode/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
  foreign="$HOME_SANDBOX/.claude/skills/$name"
  mkdir -p "$foreign"
  echo "someone else's" >"$foreign/SKILL.md"

  HOME="$HOME_SANDBOX" run "$SETUP"
  [ "$status" -eq 0 ]
  [ ! -L "$foreign" ]
  grep -q "someone else's" "$foreign/SKILL.md"

  # What dropping the guard actually does, and the only part a caller sees:
  # `ln -nsf` onto a real directory does not replace it, it links *into* it, so
  # the skill quietly lands one level down and never loads. The directory
  # surviving is not evidence the guard ran; an empty one next to SKILL.md is.
  run find "$foreign" -mindepth 1 -not -name SKILL.md
  [ -z "$output" ]
}

@test "exits 0 but reports MISS when a link could not be made" {
  # A real directory where the rules link belongs: ln puts the source *inside*
  # it instead of replacing it, so the rules never become readable at that path.
  mkdir -p "$HOME_SANDBOX/.claude/rules/dotfiles"

  HOME="$HOME_SANDBOX" run "$SETUP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISS rules"* ]]
  [[ "$output" == *"will not load this session"* ]]
}
