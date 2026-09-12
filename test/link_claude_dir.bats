#!/usr/bin/env bats

# Behavioural tests for bin/link_claude_dir.sh.
#
# Like mklink_rmworld_behaviour.bats these RUN the real script against a
# throwaway $HOME, because what is worth proving is what it does to a
# container: that the ~/.claude entries arrive, that *only* those do (a
# container that acquired .zshrc or .gitconfig is the failure this script
# exists to avoid), that --cloud is what decides whether a rule true only of a
# container comes with them, and that a link it could not make is visible —
# the Setup script field swallows the exit status, so the MISS line is the
# only signal left.

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

  # Every skill in the repo, not a list repeated here: a skill added upstream
  # must arrive without this test being edited, which is the property the walk
  # buys over mklink.sh's named entries.
  for skill in "$REPO_ROOT"/claudecode/skills/*/; do
    name="$(basename "$skill")"
    [ -L "$HOME_SANDBOX/.claude/skills/$name" ]
    [ -f "$HOME_SANDBOX/.claude/skills/$name/SKILL.md" ]
  done
}

@test "--cloud decides whether the container-only rule comes along" {
  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -eq 0 ]
  # Without it, nothing that is false on a workstation can reach one.
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

  # What dropping the guard actually does, and the only part a caller sees:
  # `ln -nsf` onto a real directory does not replace it, it links *into* it, so
  # the skill quietly lands one level down and never loads. The directory
  # surviving is not evidence the guard ran; an empty one next to SKILL.md is.
  run find "$foreign" -mindepth 1 -not -name SKILL.md
  [ -z "$output" ]
}

@test "the rules check follows the link, not one rule's filename" {
  # Pinning the health check to a named rule turns retiring that rule into a
  # MISS on a link that is fine — a false alarm in the only output a container
  # shows. Any rule in there has to satisfy it.
  fake_repo="$HOME_SANDBOX/repo"
  mkdir -p "$fake_repo/bin" "$fake_repo/claudecode/rules" "$fake_repo/claudecode/skills"
  cp "$LINK" "$fake_repo/bin/"
  : >"$fake_repo/claudecode/rules/something-else.md"

  HOME="$HOME_SANDBOX" run "$fake_repo/bin/link_claude_dir.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   rules"* ]]
}

@test "a link it could not make is reported, and changes the exit status" {
  # A real directory where the rules link belongs: ln puts the source *inside*
  # it instead of replacing it, so the rules never become readable at that path.
  mkdir -p "$HOME_SANDBOX/.claude/rules/dotfiles"

  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS rules"* ]]
}
