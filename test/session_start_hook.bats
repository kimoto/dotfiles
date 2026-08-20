#!/usr/bin/env bats

# Tests for .claude/hooks/session-start.sh, the SessionStart hook that
# provisions the lint toolchain inside Claude Code's ephemeral web sandbox.
#
# The hook installs things, so every case runs it against a throwaway
# CLAUDE_PROJECT_DIR with a stubbed bin/install_check_tools.sh and a PATH that
# holds nothing but stubs plus an allow-list of the real commands the hook
# needs: each stub records its call in $TMP/calls. The local (non-remote) case
# is the one that must never touch the machine.
#
# "Nothing but stubs" has to be literal. That PATH used to end in /usr/bin:/bin
# "for the shell itself", which quietly handed the hook everything else the host
# had installed — so on any machine carrying fzf (the very web sandbox this hook
# provisions, for one) `command -v fzf` succeeded and the "installs fzf only
# when it is missing" case failed, while passing on a bare CI runner. The
# sandbox PATH is now an allow-list, and it is applied to the hook alone rather
# than exported over the whole test, so bats' own helpers keep a working PATH
# and that list stays a statement about the hook's dependencies.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  HOOK="$REPO_ROOT/.claude/hooks/session-start.sh"
  TMP="$(mktemp -d)"

  mkdir -p "$TMP/bin" "$TMP/sysbin" "$TMP/repo/bin"
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

  # The real commands the hook needs, symlinked in one at a time. `id` (via
  # as_root) is currently the only one; everything else it runs is a shell
  # builtin or stubbed above. Listing them explicitly is what makes the sandbox
  # deterministic: a command the hook grows a dependency on is then absent on
  # every machine alike until it is added here, rather than present or missing
  # depending on what the host happens to carry.
  for real in id; do
    real_path="$(command -v "$real")" || return 1
    ln -s "$real_path" "$TMP/sysbin/$real"
  done

  SANDBOX_PATH="$TMP/bin:$TMP/sysbin"
  export CLAUDE_PROJECT_DIR="$TMP/repo"
}

teardown() {
  rm -rf "$TMP"
}

calls() { cat "$TMP/calls" 2>/dev/null; }

# Run the hook under the sandbox PATH. Any arguments are env(1) options or
# assignments and must precede the PATH operand: GNU env stops reading options
# at the first operand, so `env PATH=... -u FOO` would look for a utility named
# `-u`.
hook() { run env "$@" PATH="$SANDBOX_PATH" "$HOOK"; }

@test "a local session is a silent no-op: nothing is installed" {
  hook -u CLAUDE_CODE_REMOTE
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(calls)" ]
}

@test "CLAUDE_CODE_REMOTE set to anything but true is still local" {
  hook CLAUDE_CODE_REMOTE=false
  [ "$status" -eq 0 ]
  [ -z "$(calls)" ]
}

@test "the web sandbox gets the pinned toolchain and the git hooks" {
  hook CLAUDE_CODE_REMOTE=true
  [ "$status" -eq 0 ]
  [[ "$(calls)" == *"install_check_tools"* ]]
  [[ "$(calls)" == *"lefthook install"* ]]
  [[ "$output" == *"[session-start]"* ]]
}

@test "the web sandbox installs fzf only when it is missing" {
  # The case only means anything while the sandbox PATH really has no fzf, so
  # probe it outright and say so: a leak back to the host PATH then reads as the
  # setup bug it is, rather than as the hook failing to install anything.
  if ( PATH="$SANDBOX_PATH"; command -v fzf >/dev/null ); then
    echo "sandbox PATH leaks an fzf from the host: $SANDBOX_PATH" >&2
    return 1
  fi

  hook CLAUDE_CODE_REMOTE=true
  [[ "$(calls)" == *"apt-get install -y -qq fzf"* ]]

  rm -f "$TMP/calls"
  printf '#!/bin/bash\n' >"$TMP/bin/fzf"
  chmod +x "$TMP/bin/fzf"
  hook CLAUDE_CODE_REMOTE=true
  [[ "$(calls)" != *"apt-get"* ]]
}
