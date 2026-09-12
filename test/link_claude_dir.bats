#!/usr/bin/env bats

# Runs the real script against a throwaway $HOME, like
# mklink_rmworld_behaviour.bats does.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINK="$REPO_ROOT/bin/link_claude_dir.sh"
  HOME_SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME_SANDBOX"
}

@test "links the rules and every skill" {
  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -eq 0 ]

  [ -L "$HOME_SANDBOX/.claude/rules/dotfiles" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/rules/dotfiles")" \
      = "$REPO_ROOT/claudecode/rules" ]

  # Not a list repeated here: one added upstream must arrive untouched.
  for skill in "$REPO_ROOT"/claudecode/skills/*/; do
    name="$(basename "$skill")"
    [ -L "$HOME_SANDBOX/.claude/skills/$name" ]
    [ -f "$HOME_SANDBOX/.claude/skills/$name/SKILL.md" ]
  done
}

@test "--cloud decides whether the container-only rule comes along" {
  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_SANDBOX/.claude/rules/dotfiles-cloud" ]

  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -eq 0 ]
  [ -f "$HOME_SANDBOX/.claude/rules/dotfiles-cloud/scope.md" ]
}

@test "links nothing outside ~/.claude" {
  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -eq 0 ]

  # The two that break a container rather than merely adding to it.
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

  HOME="$HOME_SANDBOX" run "$LINK"
  [ ! -L "$foreign" ]
  grep -q "someone else's" "$foreign/SKILL.md"

  # `ln -nsf` links *into* a real directory, so the directory surviving is not
  # evidence the guard ran. An empty one is.
  run find "$foreign" -mindepth 1 -not -name SKILL.md
  [ -z "$output" ]
}

@test "the rules check follows the link, not one rule's filename" {
  # Retiring a rule must not read as a broken link.
  fake_repo="$HOME_SANDBOX/repo"
  mkdir -p "$fake_repo/bin" "$fake_repo/claudecode/rules" "$fake_repo/claudecode/skills"
  cp "$LINK" "$fake_repo/bin/"
  : >"$fake_repo/claudecode/rules/something-else.md"

  HOME="$HOME_SANDBOX" run "$fake_repo/bin/link_claude_dir.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   rules"* ]]
}

@test "a link it could not make is reported, and changes the exit status" {
  # ln goes inside a real directory, so the link never becomes readable.
  mkdir -p "$HOME_SANDBOX/.claude/rules/dotfiles"

  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS rules"* ]]
}
