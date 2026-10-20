#!/usr/bin/env bats

# Runs the SessionStart hook command from claudecode/settings-cloud.json, as
# written there, against a throwaway $HOME whose settings.json links into a
# clone of a throwaway upstream. A cloud environment restores $HOME from a cache
# taken when its setup script last ran — this hook's text included — so a skill
# added since then has no link unless the hook makes one, and a fix to the
# refresh script must take effect from the copy the pull brings in.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"
  UPSTREAM="$TMP/upstream"
  CHECKOUT="$TMP/checkout"
  mkdir -p "$UPSTREAM/bin" "$UPSTREAM/claudecode/rules" "$UPSTREAM/claudecode/rules-cloud" \
    "$TMP/home/.claude"
  cp "$REPO_ROOT/bin/link_claude_dir.sh" "$REPO_ROOT/bin/refresh_cloud_session.sh" "$UPSTREAM/bin/"
  cp "$REPO_ROOT/claudecode/settings-cloud.json" "$UPSTREAM/claudecode/"
  : >"$UPSTREAM/claudecode/rules/a.md"
  : >"$UPSTREAM/claudecode/rules-cloud/a.md"
  git -C "$UPSTREAM" init -q -b main
  # -f here and below: where mklink ran, ~/.gitignore is this repo's, which
  # ignores claudecode/skills/* outside its allow-list.
  git -C "$UPSTREAM" add -A -f
  git -C "$UPSTREAM" -c user.name=t -c user.email=t@t commit -qm init
  git clone -q "$UPSTREAM" "$CHECKOUT"
  ln -s "$CHECKOUT/claudecode/settings-cloud.json" "$TMP/home/.claude/settings.json"
  HOOK="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$CHECKOUT/claudecode/settings-cloud.json")"
}

teardown() {
  rm -rf "$TMP"
}

upstream_commit() {
  git -C "$UPSTREAM" add -A -f
  git -C "$UPSTREAM" -c user.name=t -c user.email=t@t commit -qm "$1"
}

@test "links a skill that arrived after the cached setup ran" {
  mkdir -p "$UPSTREAM/claudecode/skills/new-skill"
  : >"$UPSTREAM/claudecode/skills/new-skill/SKILL.md"
  upstream_commit "add skill"
  HOME="$TMP/home" run sh -c "$HOOK"
  [ "$status" -eq 0 ]
  [ -L "$TMP/home/.claude/skills/new-skill" ]
  [ -f "$TMP/home/.claude/skills/new-skill/SKILL.md" ]
}

@test "runs the refresh script the pull brought in, not the cached one" {
  sed -i.bak 's|^exec "$BASE_DIR/bin/link_claude_dir.sh" --cloud$|: >"$HOME/ran-new-copy"\n&|' \
    "$UPSTREAM/bin/refresh_cloud_session.sh"
  rm "$UPSTREAM/bin/refresh_cloud_session.sh.bak"
  grep -q ran-new-copy "$UPSTREAM/bin/refresh_cloud_session.sh"
  upstream_commit "change refresh"
  HOME="$TMP/home" run sh -c "$HOOK"
  [ -f "$TMP/home/ran-new-copy" ]
}

@test "leaves a checkout on another branch where it is" {
  git -C "$CHECKOUT" checkout -qb work
  mkdir -p "$UPSTREAM/claudecode/skills/new-skill"
  : >"$UPSTREAM/claudecode/skills/new-skill/SKILL.md"
  upstream_commit "add skill"
  run "$CHECKOUT/bin/refresh_cloud_session.sh"
  [[ "$output" == *"pull skipped: on 'work'"* ]]
  [ "$(git -C "$CHECKOUT" branch --show-current)" = work ]
  [ ! -e "$CHECKOUT/claudecode/skills/new-skill" ]
}

@test "prints nothing, so a session never starts with link noise" {
  HOME="$TMP/home" run sh -c "$HOOK"
  [ -z "$output" ]
}

@test "names the rules and settings that moved since the session started" {
  HOME="$TMP/home" run sh -c "$HOOK"
  echo new >"$UPSTREAM/claudecode/rules/a.md"
  : >"$UPSTREAM/claudecode/rules-cloud/b.md"
  git -C "$UPSTREAM" rm -q claudecode/rules-cloud/a.md
  echo '{}' >"$UPSTREAM/claudecode/settings-cloud.json"
  upstream_commit "move rules"
  HOME="$TMP/home" run "$CHECKOUT/bin/refresh_cloud_session.sh"
  [[ "$output" == *"rule changed: $CHECKOUT/claudecode/rules/a.md"* ]]
  [[ "$output" == *"rule changed: $CHECKOUT/claudecode/rules-cloud/b.md"* ]]
  [[ "$output" == *"rule removed: $CHECKOUT/claudecode/rules-cloud/a.md"* ]]
  [[ "$output" == *"next session: claudecode/settings-cloud.json"* ]]
}

@test "counts a rule the startup pull brought in, since it may have loaded first" {
  echo new >"$UPSTREAM/claudecode/rules/a.md"
  upstream_commit "change rule"
  HOME="$TMP/home" run sh -c "$HOOK"
  HOME="$TMP/home" run "$CHECKOUT/bin/refresh_cloud_session.sh"
  [[ "$output" == *"rule changed: $CHECKOUT/claudecode/rules/a.md"* ]]
}

@test "names no rule when none moved" {
  HOME="$TMP/home" run sh -c "$HOOK"
  HOME="$TMP/home" run "$CHECKOUT/bin/refresh_cloud_session.sh"
  [[ "$output" != *"rule "* ]]
  [[ "$output" != *"next session"* ]]
}
