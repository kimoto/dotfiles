#!/usr/bin/env bats

# Tests for .claude/hooks/session-start.sh, the SessionStart hook that
# provisions the lint toolchain inside Claude Code's ephemeral web sandbox.
#
# The hook installs things, so every case runs it against a throwaway
# CLAUDE_PROJECT_DIR with a stubbed bin/install_check_tools.sh and a PATH that
# holds nothing but stubs: each stub records its call in $TMP/calls. The local
# (non-remote) case is the one that must never touch the machine.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  HOOK="$REPO_ROOT/.claude/hooks/session-start.sh"
  TMP="$(mktemp -d)"

  mkdir -p "$TMP/bin" "$TMP/repo/bin"
  for stub in lefthook sudo apt-get; do
    cat >"$TMP/bin/$stub" <<EOF
#!/bin/bash
echo "$stub \$*" >>"$TMP/calls"
EOF
    chmod +x "$TMP/bin/$stub"
  done

  cat >"$TMP/repo/bin/install_check_tools.sh" <<EOF
#!/bin/bash
echo "install_check_tools" >>"$TMP/calls"
EOF
  chmod +x "$TMP/repo/bin/install_check_tools.sh"

  # Stubs first, then the bare minimum for the shell itself; notably no fzf.
  export PATH="$TMP/bin:/usr/bin:/bin"
  export CLAUDE_PROJECT_DIR="$TMP/repo"
}

teardown() {
  rm -rf "$TMP"
}

calls() { cat "$TMP/calls" 2>/dev/null; }

@test "a local session is a silent no-op: nothing is installed" {
  run env -u CLAUDE_CODE_REMOTE "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(calls)" ]
}

@test "CLAUDE_CODE_REMOTE set to anything but true is still local" {
  CLAUDE_CODE_REMOTE=false run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$(calls)" ]
}

@test "the web sandbox gets the pinned toolchain and the git hooks" {
  CLAUDE_CODE_REMOTE=true run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [[ "$(calls)" == *"lefthook install"* ]]
  [[ "$output" == *"[session-start]"* ]]
}

@test "the web sandbox installs fzf only when it is missing" {
  CLAUDE_CODE_REMOTE=true run "$HOOK"
  [[ "$(calls)" == *"apt-get install -y -qq fzf"* ]]

  rm -f "$TMP/calls"
  printf '#!/bin/bash\n' >"$TMP/bin/fzf"
  chmod +x "$TMP/bin/fzf"
  CLAUDE_CODE_REMOTE=true run "$HOOK"
  [[ "$(calls)" != *"apt-get"* ]]
}
