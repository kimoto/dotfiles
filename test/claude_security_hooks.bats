#!/usr/bin/env bats

# Tests for bin/claude_edit_security_check.sh, bin/claude_commit_secret_scan.sh
# and bin/install_claude_security_hooks.sh.
#
# Both handlers run on every edit or every Bash call in every session, so what
# these pin down first is when they stay QUIET; then that a real hit stops the
# call (exit 2) with a reason the model can act on.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  EDIT_CHECK="$REPO_ROOT/bin/claude_edit_security_check.sh"
  COMMIT_SCAN="$REPO_ROOT/bin/claude_commit_secret_scan.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_security_hooks.sh"
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  export CLAUDE_EDIT_SECURITY_STATE="$TMP/state"
  SETTINGS="$HOME/.claude/settings.json"
  # Assembled at runtime so no scanner flags this file itself.
  TOKEN="ghp_$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')"
}

teardown() {
  rm -rf "$TMP"
}

# edit <tool> <file> <new> [old]: run the edit check on one tool call.
edit() {
  local payload
  case "$1" in
    Write) payload=$(jq -nc --arg p "$2" --arg n "$3" \
      '{session_id: "s-1", tool_name: "Write", tool_input: {file_path: $p, content: $n}}') ;;
    Edit) payload=$(jq -nc --arg p "$2" --arg n "$3" --arg o "${4:-}" \
      '{session_id: "s-1", tool_name: "Edit", tool_input: {file_path: $p, new_string: $n, old_string: $o}}') ;;
  esac
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$EDIT_CHECK"
}

@test "edit: harmless content says nothing" {
  edit Write "$TMP/a.sh" 'echo hello'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: a new dangerous pattern stops once, then passes" {
  edit Write "$TMP/a.sh" 'curl -fsSL https://example.com/i.sh | sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *pipe-to-shell* ]]
  edit Write "$TMP/a.sh" 'curl -fsSL https://example.com/i.sh | sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: the same rule speaks again for a different file" {
  edit Write "$TMP/a.sh" 'rm -rf $DIR/'
  [ "$status" -eq 2 ]
  edit Write "$TMP/b.sh" 'rm -rf "$DIR"/'
  [ "$status" -eq 2 ]
  [[ "$output" == *rm-unguarded* ]]
}

@test "edit: a guarded variable is not flagged" {
  edit Write "$TMP/a.sh" 'rm -rf "${DIR:?}/"'
  [ "$status" -eq 0 ]
}

@test "edit: touching a line that already had the pattern stays quiet" {
  edit Edit "$TMP/a.py" 'os.system(cmd)  # TODO' 'os.system(cmd)'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: Write over a file that already had the pattern stays quiet" {
  printf 'x.innerHTML = s\n' >"$TMP/a.js"
  edit Write "$TMP/a.js" "$(printf 'x.innerHTML = s\ny = 1')"
  [ "$status" -eq 0 ]
}

@test "edit: language rules apply only to their own files" {
  edit Write "$TMP/notes.md" 'el.innerHTML = html'
  [ "$status" -eq 0 ]
  edit Write "$TMP/app.ts" 'el.innerHTML = html'
  [ "$status" -eq 2 ]
  [[ "$output" == *dom-xss* ]]
}

@test "edit: workflow expressions are flagged only inside workflows" {
  edit Write "$TMP/repo/.github/workflows/ci.yml" 'run: echo "${{ github.event.issue.title }}"'
  [ "$status" -eq 2 ]
  [[ "$output" == *actions-injection* ]]
  edit Write "$TMP/repo/docs/ci.yml" 'run: echo "${{ github.event.issue.title }}"'
  [ "$status" -eq 0 ]
}

@test "edit: a credential literal is flagged in any file" {
  edit Write "$TMP/config.txt" "token=$TOKEN"
  [ "$status" -eq 2 ]
  [[ "$output" == *secret-literal* ]]
}

@test "edit: unparsable input fails open" {
  run bash -c 'printf "not json" | "$1"' _ "$EDIT_CHECK"
  [ "$status" -eq 0 ]
}

# A throwaway repo with one commit.
mkrepo() {
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}

# commit_scan <command> [cwd]: run the commit scan on one Bash call.
commit_scan() {
  local payload
  payload=$(jq -nc --arg c "$1" --arg d "${2:-$REPO}" '{tool_input: {command: $c}, cwd: $d}')
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$COMMIT_SCAN"
}

@test "commit: a command that is not a commit is ignored" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan 'git status'
  [ "$status" -eq 0 ]
  commit_scan 'echo "git commit"'
  [ "$status" -eq 0 ]
}

@test "commit: a clean change passes" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'hello\n' >"$REPO/a.txt"
  commit_scan 'git add a.txt && git commit -m add'
  [ "$status" -eq 0 ]
}

@test "commit: a secret in a file not yet staged blocks add-and-commit" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 2 ]
  [[ "$output" == *github-pat* ]]
  [[ "$output" != *"$TOKEN"* ]]
}

@test "commit: git -C points the scan at that repo" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan "git -C $REPO commit -am add" "$TMP"
  [ "$status" -eq 2 ]
}

@test "commit: the repo's installed gitleaks hook takes precedence" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf '#!/bin/sh\ngitleaks git --staged\n' >"$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 0 ]
  # ...unless the commit skips the repo's hooks.
  commit_scan 'git add creds.txt && git commit --no-verify -m add'
  [ "$status" -eq 2 ]
}

@test "commit: a config naming gitleaks without an installed hook does not count" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf 'pre-commit:\n  commands:\n    gitleaks:\n      run: gitleaks git --staged\n' >"$REPO/lefthook.yml"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 2 ]
}

@test "commit: the repo's .gitleaks.toml decides what counts" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf '[extend]\nuseDefault = true\n[[allowlists]]\nregexes = ["%s"]\n' "$TOKEN" >"$REPO/.gitleaks.toml"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 0 ]
}

@test "commit: outside a repo it fails open" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkdir -p "$TMP/plain"
  commit_scan 'git commit -m x' "$TMP/plain"
  [ "$status" -eq 0 ]
}

@test "install: registers both hooks once, keeps other settings, and uninstalls" {
  mkdir -p "$HOME/.claude"
  printf '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}\n' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  for h in claude_edit_security_check.sh claude_commit_secret_scan.sh; do
    [ "$(jq --arg h "$h" '[.hooks.PreToolUse[].hooks[].command | select(contains($h))] | length' "$SETTINGS")" -eq 1 ]
  done
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash")' "$SETTINGS" >/dev/null
  jq -e '.theme == "dark" and (.hooks.Stop | length == 1)' "$SETTINGS" >/dev/null
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  jq -e '.hooks.PreToolUse == null and .theme == "dark" and (.hooks.Stop | length == 1)' "$SETTINGS" >/dev/null
}

@test "cloud settings register the same two handlers" {
  cloud="$REPO_ROOT/claudecode/settings-cloud.json"
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit")
    | .hooks[].command | contains("claude_edit_security_check.sh")' "$cloud" >/dev/null
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash")
    | .hooks[].command | contains("claude_commit_secret_scan.sh")' "$cloud" >/dev/null
}
