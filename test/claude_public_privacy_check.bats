#!/usr/bin/env bats

# Tests for bin/claude_public_privacy_check.sh: what an agent is about to
# publish to a public repo reaches the reviewer, its verdict blocks or passes
# the call, and a private repo or an unrelated command never asks it. The
# model is replaced by PRIVACY_JUDGE, which flags the word "secretword".

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  CHECK="$REPO_ROOT/bin/claude_public_privacy_check.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME/public-privacy-check"
  # Records what it was asked, so a test can show the reviewer never ran.
  export ASKED="$TMP/asked"
  export PRIVACY_JUDGE='tee "$ASKED" | grep -q secretword &&
    echo "{\"private\":true,\"quotes\":[\"secretword\"],\"why\":\"names a relative\"}" ||
    echo "{\"private\":false}"'
}

teardown() {
  rm -rf "$TMP"
}

# visibility <owner> <repo> public|private: answer for is_public without the network.
visibility() {
  printf '%s\n' "$3" >"$XDG_STATE_HOME/public-privacy-check/$1%$2"
}

# mkrepo <owner/repo>: a repo whose origin is that GitHub repo, one commit in.
mkrepo() {
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" remote add origin "https://github.com/$1.git"
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}

hook() {
  run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$CHECK"
}

# bash_hook <command>: the hook on a Bash call run in $REPO.
bash_hook() {
  hook "$(jq -nc --arg d "$REPO" --arg c "$1" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}')"
}

@test "commit: an untracked file the command adds is reviewed and blocks" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  bash_hook "git add a.txt && git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"secretword"'* ]]
  [[ "$output" == *"names a relative"* ]]
}

@test "commit: a staged change is reviewed" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt
  bash_hook "git commit -m x"
  [ "$status" -eq 2 ]
  grep -q "change to commit" "$ASKED"
}

@test "commit: the message in the command is reviewed, and a clean one passes" {
  mkrepo o/pub
  visibility o pub public
  bash_hook "git commit -m \"about the secretword\""
  [ "$status" -eq 2 ]
  bash_hook "git commit -m \"fix: a typo\""
  [ "$status" -eq 0 ]
}

@test "push: unpushed commits are reviewed" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m "add a"
  bash_hook "git push -u origin x"
  [ "$status" -eq 2 ]
}

@test "gh pr create --body-file: the file is reviewed" {
  mkrepo o/pub
  visibility o pub public
  printf 'Summary\n\nsecretword\n' >"$TMP/body.md"
  bash_hook "gh pr create --title t --body-file $TMP/body.md"
  [ "$status" -eq 2 ]
  grep -q "=== body.md ===" "$ASKED"
}

@test "GitHub MCP: a write to a public repo is reviewed, a read is not" {
  visibility o pub public
  hook '{"tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"o","repo":"pub","body":"secretword"}}'
  [ "$status" -eq 2 ]
  rm -f "$ASKED"
  hook '{"tool_name":"mcp__github__list_issues","tool_input":{"owner":"o","repo":"pub","query":"secretword"}}'
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
}

@test "a private repo never asks the reviewer" {
  mkrepo o/priv
  visibility o priv private
  printf 'secretword\n' >"$REPO/a.txt"
  bash_hook "git add a.txt && git commit -m x"
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
  hook '{"tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"o","repo":"priv","body":"secretword"}}'
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
}

@test "an unrelated command never asks the reviewer" {
  mkrepo o/pub
  visibility o pub public
  bash_hook "grep secretword notes.txt"
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
}

@test "a reply that is not a verdict fails open" {
  mkrepo o/pub
  visibility o pub public
  export PRIVACY_JUDGE='cat >/dev/null; echo "I cannot help with that"'
  bash_hook "git commit -m \"about the secretword\""
  [ "$status" -eq 0 ]
}

@test "install and cloud settings register the hook for Bash and GitHub MCP calls" {
  mkdir -p "$HOME/.claude"
  printf '{}\n' >"$HOME/.claude/settings.json"
  run "$REPO_ROOT/bin/install_claude_secret_scan_hook.sh"
  [ "$status" -eq 0 ]
  for f in "$HOME/.claude/settings.json" "$REPO_ROOT/claudecode/settings-cloud.json"; do
    jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|mcp__.*github.*")
      | .hooks[].command | contains("claude_public_privacy_check.sh")' "$f" >/dev/null
  done
  run "$REPO_ROOT/bin/install_claude_secret_scan_hook.sh" --uninstall
  jq -e '.hooks.PreToolUse == null' "$HOME/.claude/settings.json" >/dev/null
}
