#!/usr/bin/env bats

# bin/setup_cloud_session.sh against a throwaway repo and $HOME, under the same
# stub-only PATH the SessionStart hook tests use — the script installs things,
# and a command it reaches for must be absent everywhere alike rather than
# present on whatever host happens to carry it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"

  mkdir -p "$TMP/bin" "$TMP/sysbin" "$TMP/decoy" "$TMP/repo/bin" \
    "$TMP/repo/claudecode/rules" "$TMP/repo/claudecode/rules-cloud" \
    "$TMP/repo/claudecode/skills/example-skill"
  : >"$TMP/repo/claudecode/rules/example.md"
  : >"$TMP/repo/claudecode/rules-cloud/scope.md"
  : >"$TMP/repo/claudecode/settings-cloud.json"
  : >"$TMP/repo/claudecode/skills/example-skill/SKILL.md"

  # The real linker, not a stub: a stub tests the call, not the result.
  cp "$REPO_ROOT/bin/setup_cloud_session.sh" "$REPO_ROOT/bin/link_claude_dir.sh" "$TMP/repo/bin/"
  SETUP="$TMP/repo/bin/setup_cloud_session.sh"

  for stub in lefthook sudo apt-get; do
    cat >"$TMP/bin/$stub" <<EOF
#!/bin/bash
echo "$stub \$*" >>"$TMP/calls"
EOF
    chmod +x "$TMP/bin/$stub"
  done

  toolchain_stub 0

  for real in id mkdir ln readlink dirname basename find; do
    real_path="$(command -v "$real")" || return 1
    ln -s "$real_path" "$TMP/sysbin/$real"
  done

  SANDBOX_PATH="$TMP/bin:$TMP/sysbin"
}

teardown() {
  rm -rf "$TMP"
}

# The one step that can half-succeed, so every case decides what it did.
toolchain_stub() {
  cat >"$TMP/repo/bin/install_check_tools.sh" <<EOF
#!/bin/bash
echo "install_check_tools" >>"$TMP/calls"
exit $1
EOF
  chmod +x "$TMP/repo/bin/install_check_tools.sh"
}

calls() { cat "$TMP/calls" 2>/dev/null; }

run_setup() { run env HOME="$TMP/home" PATH="$SANDBOX_PATH" "$SETUP"; }

@test "a container gets the toolchain, the git hooks and the ~/.claude entries" {
  run_setup
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [[ "$(calls)" == *"lefthook install"* ]]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  [ -L "$TMP/home/.claude/skills/example-skill" ]
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
  run env -C "$TMP/decoy" HOME="$TMP/home" PATH="$SANDBOX_PATH" "$SETUP"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/home/.claude/rules/dotfiles")" = "$TMP/repo/claudecode/rules" ]
  [ ! -e "$TMP/decoy/claudecode" ]
}
