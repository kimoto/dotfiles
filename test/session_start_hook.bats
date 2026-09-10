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

  # The rules directory has to really exist: `ln -sf` onto an existing symlink
  # only dereferences it — and nests the second link inside — when the target is
  # a real directory. A dangling link would hide that difference, and with it
  # the reason the hook passes -n.
  mkdir -p "$TMP/bin" "$TMP/sysbin" "$TMP/repo/bin" "$TMP/repo/claudecode/rules"
  : >"$TMP/repo/claudecode/rules/example.md"
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

  # The real commands the hook needs, symlinked in one at a time: `id` (via
  # as_root), and mkdir/ln for the rules link. Everything else it runs is a
  # shell builtin or stubbed above. Listing them explicitly is what makes the
  # sandbox deterministic: a command the hook grows a dependency on is then
  # absent on every machine alike until it is added here, rather than present or
  # missing depending on what the host happens to carry.
  for real in id mkdir ln; do
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
#
# HOME is redirected too, because the hook links this repo's rules into
# $HOME/.claude/rules/. Left at the real one, running the suite would rewrite
# the developer's own Claude Code configuration.
hook() { run env "$@" HOME="$TMP/home" PATH="$SANDBOX_PATH" "$HOOK"; }

@test "a local session is a silent no-op: nothing is installed" {
  hook -u CLAUDE_CODE_REMOTE
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(calls)" ]
  # On a real machine mkworld.sh owns ~/.claude; the hook must not reach in.
  [ ! -e "$TMP/home/.claude" ]
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

# --- repo rules --------------------------------------------------------------
#
# ~/.claude/rules/ is a conf.d that Claude Code loads into every session on the
# machine. bin/mklink.sh fills it on a real machine and nothing filled it here,
# so a rule this repo keeps for every session was reaching local sessions only.

@test "the web sandbox links the repo's rules into ~/.claude/rules" {
  hook CLAUDE_CODE_REMOTE=true
  [ "$status" -eq 0 ]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  [ "$(readlink "$TMP/home/.claude/rules/dotfiles")" = "$CLAUDE_PROJECT_DIR/claudecode/rules" ]
}

@test "linking the rules is idempotent" {
  hook CLAUDE_CODE_REMOTE=true
  hook CLAUDE_CODE_REMOTE=true
  [ "$status" -eq 0 ]
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
  # The damage a missing -n does lands in the repo, not here: `ln -s` onto an
  # existing symlink dereferences it, so the second run drops a stray link
  # *inside* claudecode/rules/ — untracked, and picked up as a rule.
  [ ! -e "$TMP/repo/claudecode/rules/rules" ]
  [ "$(find "$TMP/home/.claude/rules" -mindepth 1 | wc -l)" -eq 1 ]
}

@test "rules linked in by another repo are left alone" {
  mkdir -p "$TMP/home/.claude/rules" "$TMP/other-repo/rules"
  ln -s "$TMP/other-repo/rules" "$TMP/home/.claude/rules/other"

  hook CLAUDE_CODE_REMOTE=true
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/home/.claude/rules/other")" = "$TMP/other-repo/rules" ]
  # Both, or this case passes while the hook does nothing at all.
  [ -L "$TMP/home/.claude/rules/dotfiles" ]
}

@test "a link it cannot make is reported, not swallowed" {
  # A file where the rules directory belongs: mkdir -p fails, and the hook has
  # to say so. Silence here would look exactly like rules that loaded.
  mkdir -p "$TMP/home/.claude"
  : >"$TMP/home/.claude/rules"

  hook CLAUDE_CODE_REMOTE=true
  [ "$status" -eq 0 ]
  [[ "$output" == *"rules"* ]]
  [[ "$output" == *"will not load"* ]]
}
