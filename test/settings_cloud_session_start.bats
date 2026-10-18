#!/usr/bin/env bats

# Runs the SessionStart hook command from claudecode/settings-cloud.json, as
# written there, against a throwaway $HOME whose settings.json links into a
# copy of this repo. A cloud environment restores $HOME from a cache taken when
# its setup script last ran, so a skill added since then has no link unless this
# hook makes one.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"
  CHECKOUT="$TMP/checkout"
  mkdir -p "$CHECKOUT/bin" "$CHECKOUT/claudecode/rules" "$CHECKOUT/claudecode/rules-cloud" \
    "$CHECKOUT/claudecode/skills/new-skill" "$TMP/home/.claude"
  cp "$REPO_ROOT/bin/link_claude_dir.sh" "$CHECKOUT/bin/"
  cp "$REPO_ROOT/claudecode/settings-cloud.json" "$CHECKOUT/claudecode/"
  : >"$CHECKOUT/claudecode/skills/new-skill/SKILL.md"
  ln -s "$CHECKOUT/claudecode/settings-cloud.json" "$TMP/home/.claude/settings.json"
  HOOK="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$CHECKOUT/claudecode/settings-cloud.json")"
}

teardown() {
  rm -rf "$TMP"
}

@test "links a skill that arrived after the cached setup ran" {
  HOME="$TMP/home" run sh -c "$HOOK"
  [ "$status" -eq 0 ]
  [ -L "$TMP/home/.claude/skills/new-skill" ]
  [ -f "$TMP/home/.claude/skills/new-skill/SKILL.md" ]
}

@test "prints nothing, so a session never starts with link noise" {
  HOME="$TMP/home" run sh -c "$HOOK"
  [ -z "$output" ]
}
