#!/usr/bin/env bats

# bin/setup_agent.sh against a throwaway repo and $HOME, under a stub-only PATH:
# the script installs things, and a command it reaches for must be absent
# everywhere alike rather than present on whatever host happens to carry it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"

  mkdir -p "$TMP/sysbin" "$TMP/decoy" "$TMP/repo/bin" "$TMP/repo/codex" \
    "$TMP/repo/claudecode/rules" "$TMP/repo/claudecode/rules-cloud" \
    "$TMP/repo/claudecode/skills/example-skill"
  : >"$TMP/repo/codex/config.toml"
  : >"$TMP/repo/codex/AGENTS.md"
  : >"$TMP/repo/claudecode/rules/example.md"
  : >"$TMP/repo/claudecode/rules-cloud/scope.md"
  : >"$TMP/repo/claudecode/settings-cloud.json"
  : >"$TMP/repo/claudecode/skills/example-skill/SKILL.md"

  # The real linker, not a stub: a stub tests the call, not the result.
  cp "$REPO_ROOT/bin/setup_agent.sh" "$REPO_ROOT/bin/link_claude_dir.sh" "$TMP/repo/bin/"
  SETUP="$TMP/repo/bin/setup_agent.sh"

  toolchain_stub 0

  for real in id mkdir ln readlink dirname basename find; do
    real_path="$(command -v "$real")" || return 1
    ln -s "$real_path" "$TMP/sysbin/$real"
  done
}

teardown() {
  rm -rf "$TMP"
}

toolchain_stub() {
  cat >"$TMP/repo/bin/install_check_tools.sh" <<STUB
#!/bin/bash
echo "install_check_tools" >>"$TMP/calls"
exit $1
STUB
  chmod +x "$TMP/repo/bin/install_check_tools.sh"
}

calls() { cat "$TMP/calls" 2>/dev/null; }

run_setup() { run env -u CODEX_HOME HOME="$TMP/home" PATH="$TMP/sysbin" "$SETUP" "$@"; }

@test "an agent container gets the toolchain and both agents' configuration" {
  run_setup
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  [ -L "$TMP/home/.claude/rules/dotfiles-cloud" ]
  [ "$(readlink -f "$TMP/home/.codex/AGENTS.md")" = "$TMP/repo/codex/AGENTS.md" ]
}

@test "a toolchain that did not land still leaves the rules in place" {
  toolchain_stub 1

  # The rules need no network; a container that cannot fetch tools still gets them.
  run_setup
  [ "$status" -ne 0 ]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  [ -L "$TMP/home/.codex/config.toml" ]
}

@test "--no-toolchain links without installing" {
  run_setup --no-toolchain
  [ "$status" -eq 0 ]
  [[ "$(calls)" != *"install_check_tools"* ]]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
}

@test "it finds its repo from itself, not from the working directory" {
  run env -u CODEX_HOME -C "$TMP/decoy" HOME="$TMP/home" PATH="$TMP/sysbin" "$SETUP"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/home/.claude/rules/dotfiles")" = "$TMP/repo/claudecode/rules" ]
}
