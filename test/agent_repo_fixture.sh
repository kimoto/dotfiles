#!/bin/bash
# A throwaway dotfiles checkout and a stub-only PATH, shared by the bats tests of
# the scripts that set up an agent container. Those scripts install things, so
# a command they reach for must be absent everywhere alike rather than present
# on whatever host happens to carry it. This file is *sourced*, not executed,
# from setup() once $TMP is set:
#
#   # shellcheck source=test/agent_repo_fixture.sh
#   . "$REPO_ROOT/test/agent_repo_fixture.sh"

# make_agent_repo: one empty file of each kind the linkers read, in $TMP/repo,
# and the real .gitconfig.agent, whose address the identity step checks.
# The rules directory has to really exist: `ln -sf` dereferences an existing
# symlink only when the target is real, so a dangling one hides the -n case.
make_agent_repo() {
  mkdir -p "$TMP/repo/bin" "$TMP/repo/codex" \
    "$TMP/repo/claudecode/rules" "$TMP/repo/claudecode/rules-cloud" \
    "$TMP/repo/claudecode/skills/example-skill"
  : >"$TMP/repo/codex/config.toml"
  cp "$REPO_ROOT/.gitconfig.agent" "$TMP/repo/"
  : >"$TMP/repo/codex/AGENTS.md"
  : >"$TMP/repo/claudecode/rules/example.md"
  : >"$TMP/repo/claudecode/rules-cloud/scope.md"
  : >"$TMP/repo/claudecode/settings-cloud.json"
  : >"$TMP/repo/claudecode/skills/example-skill/SKILL.md"
}

# call_stubs <command>...: a stub in $TMP/bin for each, recording the call.
call_stubs() {
  local stub
  mkdir -p "$TMP/bin"
  for stub in "$@"; do
    cat >"$TMP/bin/$stub" <<EOF
#!/bin/bash
echo "$stub \$*" >>"$TMP/calls"
EOF
    chmod +x "$TMP/bin/$stub"
  done
}

# toolchain_stub <status>: bin/install_check_tools.sh records its call and
# exits <status>. It is the one step that can half-succeed, so a case can
# decide what it did.
toolchain_stub() {
  cat >"$TMP/repo/bin/install_check_tools.sh" <<EOF
#!/bin/bash
echo "install_check_tools" >>"$TMP/calls"
exit $1
EOF
  chmod +x "$TMP/repo/bin/install_check_tools.sh"
}

# link_real <command>...: the real commands, symlinked into $TMP/sysbin one at
# a time. Naming each one keeps the sandbox an allow-list: a command the script
# grows a dependency on stays absent on every machine until it is added here.
link_real() {
  local real real_path
  mkdir -p "$TMP/sysbin"
  for real in "$@"; do
    real_path="$(command -v "$real")" || return 1
    ln -s "$real_path" "$TMP/sysbin/$real"
  done
}

calls() { cat "$TMP/calls" 2>/dev/null; }
