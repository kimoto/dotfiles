#!/usr/bin/env bats

# bin/setup_agent.sh against a throwaway repo and $HOME, under a stub-only PATH:
# the script installs things, and a command it reaches for must be absent
# everywhere alike rather than present on whatever host happens to carry it.

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
  cp "$REPO_ROOT/bin/setup_agent.sh" "$REPO_ROOT/bin/link_claude_dir.sh" \
    "$REPO_ROOT/bin/link_git_identity.sh" "$TMP/repo/bin/"
  cp "$REPO_ROOT/.gitconfig.agent" "$TMP/repo/"
  mkdir -p "$TMP/home"
  SETUP="$TMP/repo/bin/setup_agent.sh"
  toolchain_stub 0
  link_real id mkdir ln readlink dirname basename find git grep
}

teardown() {
  rm -rf "$TMP"
}

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

@test "commits in the container are authored by the owner, once however often it runs" {
  # The platform's own author comes first, as in a real container.
  printf '[user]\n\tname = Claude\n\temail = noreply@anthropic.com\n' >"$TMP/home/.gitconfig"

  run_setup
  [ "$status" -eq 0 ]
  run_setup
  [ "$status" -eq 0 ]
  [ "$(HOME="$TMP/home" git config --includes user.email)" = "kimoto@users.noreply.github.com" ]
  [ "$(HOME="$TMP/home" git config --global --get-all include.path | wc -l)" -eq 1 ]
}

@test "a ~/.gitconfig that is a symlink is not written through" {
  # On a workstation mklink.sh links it into this repo; a write would land there.
  printf '[user]\n\tname = someone\n' >"$TMP/linked.gitconfig"
  ln -s "$TMP/linked.gitconfig" "$TMP/home/.gitconfig"

  run_setup
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISS git identity"* ]]
  [ "$(grep -c include "$TMP/linked.gitconfig")" -eq 0 ]
}

@test "the container's author is the workstation's author" {
  for key in user.name user.email; do
    [ "$(git config --file "$REPO_ROOT/.gitconfig.agent" "$key")" = \
      "$(git config --file "$REPO_ROOT/.gitconfig.default_user" "$key")" ]
  done
}
