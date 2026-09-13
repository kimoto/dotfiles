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

@test "a run without --cloud takes the container-only rule back out" {
  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -eq 0 ]
  [ -f "$HOME_SANDBOX/.claude/rules/dotfiles-cloud/scope.md" ]

  # Every line of rules-cloud is false outside a container, so one inherited
  # from an earlier run reads as truth about this machine.
  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME_SANDBOX/.claude/rules/dotfiles-cloud" ]
  [ ! -e "$HOME_SANDBOX/.claude/rules/dotfiles-cloud" ]
}

@test "a skill left alone is not reported as one that linked" {
  name="$(basename "$(find "$REPO_ROOT/claudecode/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
  foreign="$HOME_SANDBOX/.claude/skills/$name"
  mkdir -p "$foreign"
  echo "someone else's" >"$foreign/SKILL.md"

  # Their SKILL.md is not ours arriving: what loads under that name is theirs,
  # which is the case the report exists to make visible.
  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -ne 0 ]
  [[ "$output" != *"ok   skill $name"* ]]
  [[ "$output" == *"MISS skill $name"* ]]
}

@test "--cloud puts the session's settings under the repo" {
  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   cloud settings"* ]]

  [ -L "$HOME_SANDBOX/.claude/settings.json" ]
  [ "$(readlink -f "$HOME_SANDBOX/.claude/settings.json")" \
      = "$REPO_ROOT/claudecode/settings-cloud.json" ]
}

@test "settings already there are never linked over" {
  mkdir -p "$HOME_SANDBOX/.claude"
  echo '{"theirs": true}' >"$HOME_SANDBOX/.claude/settings.json"

  # Claude Code's own path: a link would take their settings into the repo.
  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS cloud settings"* ]]

  [ ! -L "$HOME_SANDBOX/.claude/settings.json" ]
  grep -q theirs "$HOME_SANDBOX/.claude/settings.json"
}

@test "a run without --cloud takes the cloud settings back out too" {
  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -eq 0 ]
  [ -L "$HOME_SANDBOX/.claude/settings.json" ]

  HOME="$HOME_SANDBOX" run "$LINK"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME_SANDBOX/.claude/settings.json" ]
  [ ! -e "$HOME_SANDBOX/.claude/settings.json" ]
}

@test "a settings symlink someone else made is left alone too" {
  mkdir -p "$HOME_SANDBOX/.claude"
  echo '{"theirs": true}' >"$HOME_SANDBOX/theirs.json"
  ln -nsf "$HOME_SANDBOX/theirs.json" "$HOME_SANDBOX/.claude/settings.json"

  HOME="$HOME_SANDBOX" run "$LINK" --cloud
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS cloud settings"* ]]
  [ "$(readlink "$HOME_SANDBOX/.claude/settings.json")" = "$HOME_SANDBOX/theirs.json" ]
}
