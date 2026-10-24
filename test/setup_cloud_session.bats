#!/usr/bin/env bats

# bin/setup_cloud_session.sh against a throwaway repo and $HOME, under the same
# stub-only PATH the SessionStart hook tests use — the script installs things,
# and a command it reaches for must be absent everywhere alike rather than
# present on whatever host happens to carry it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  # shellcheck source=test/agent_repo_fixture.sh
  . "$REPO_ROOT/test/agent_repo_fixture.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"

  mkdir -p "$TMP/decoy"
  make_agent_repo
  # The real linker, not a stub: a stub tests the call, not the result.
  cp "$REPO_ROOT/bin/setup_cloud_session.sh" "$REPO_ROOT/bin/setup_agent.sh" \
    "$REPO_ROOT/bin/link_claude_dir.sh" "$TMP/repo/bin/"
  SETUP="$TMP/repo/bin/setup_cloud_session.sh"
  call_stubs lefthook sudo apt-get
  toolchain_stub 0
  link_real id mkdir ln readlink dirname basename find

  SANDBOX_PATH="$TMP/bin:$TMP/sysbin"
}

teardown() {
  rm -rf "$TMP"
}

run_setup() { run env -u CODEX_HOME HOME="$TMP/home" PATH="$SANDBOX_PATH" "$SETUP"; }

@test "a container gets the toolchain, hooks, and user configuration" {
  run_setup
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [[ "$(calls)" == *"lefthook install"* ]]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  [ -L "$TMP/home/.claude/skills/example-skill" ]
  [ "$(readlink -f "$TMP/home/.codex/config.toml")" = "$TMP/repo/codex/config.toml" ]
  [ "$(readlink -f "$TMP/home/.codex/AGENTS.md")" = "$TMP/repo/codex/AGENTS.md" ]
}

@test "a toolchain that did not land leaves the git hooks alone" {
  toolchain_stub 1

  # Installed here they would refuse every commit instead of checking it.
  run_setup
  [ "$status" -ne 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [[ "$(calls)" != *"lefthook install"* ]]
  [[ "$output" == *"MISS git hooks"* ]]
}

@test "lefthook missing is reported, not passed over in silence" {
  rm -f "$TMP/bin/lefthook"

  run_setup
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS git hooks"* ]]
  # The rest of the container still gets set up.
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
}

@test "it finds its repo from itself, not from the working directory" {
  # The case that left this checkout with no hooks.
  run env -u CODEX_HOME -C "$TMP/decoy" HOME="$TMP/home" PATH="$SANDBOX_PATH" "$SETUP"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/home/.claude/rules/dotfiles")" = "$TMP/repo/claudecode/rules" ]
  [ ! -e "$TMP/decoy/claudecode" ]
}

@test "an existing Codex config is preserved and reported" {
  mkdir -p "$TMP/home/.codex"
  printf 'foreign\n' >"$TMP/home/.codex/config.toml"

  run_setup

  [ "$status" -ne 0 ]
  [ "$(cat "$TMP/home/.codex/config.toml")" = foreign ]
  [[ "$output" == *"MISS Codex config"* ]]
  # Independent entries still land, so repairing the collision is sufficient.
  [ -L "$TMP/home/.codex/AGENTS.md" ]
}
