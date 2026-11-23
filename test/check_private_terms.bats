#!/usr/bin/env bats

# Tests for bin/check_private_terms.sh: a private word bound for a public repo
# is stopped in every place it can leave from, a private repo is left alone,
# and CI's redacted report never repeats the word.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  CHECK="$REPO_ROOT/bin/check_private_terms.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME/private-terms"
  export PRIVATE_TERMS=$'# a comment line\nsecretword\nhidden[ -]?place'
  unset PRIVATE_TERMS_REDACT PRIVATE_TERMS_FILE
}

teardown() {
  rm -rf "$TMP"
}

# visibility <owner> <repo> public|private: answer for is_public without the network.
visibility() {
  printf '%s\n' "$3" >"$XDG_STATE_HOME/private-terms/$1%$2"
}

# mkrepo <owner/repo>: a repo whose origin is that GitHub repo, one commit in.
mkrepo() {
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" remote add origin "https://github.com/$1.git"
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}

commit() {
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q "$@"
}

# hook <json payload>
hook() {
  run bash -c 'printf "%s" "$1" | "$2" claude-hook' _ "$1" "$CHECK"
}

# bash_hook <command>: the hook on a Bash call run in $REPO.
bash_hook() {
  hook "$(jq -nc --arg d "$REPO" --arg c "$1" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}')"
}

@test "text: a listed word fails and is named" {
  run bash -c 'printf "fine\nat the Hidden-Place\n" | "$1" text "PR body"' _ "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *'PR body line 2: matches "hidden[ -]?place"'* ]]
}

@test "text: redacted report says where, never the word" {
  run bash -c 'printf "SecretWord\n" | PRIVATE_TERMS_REDACT=1 "$1" text "PR body"' _ "$CHECK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PR body line 1"* ]]
  [[ "${output,,}" != *secretword* ]]
}

@test "text: clean text and a missing list both pass" {
  run bash -c 'printf "nothing here\n" | "$1" text body' _ "$CHECK"
  [ "$status" -eq 0 ]
  run bash -c 'printf "secretword\n" | PRIVATE_TERMS= "$1" text body' _ "$CHECK"
  [ "$status" -eq 0 ]
}

@test "text: the list can come from a file" {
  printf 'fileword\n' >"$TMP/terms"
  run bash -c 'printf "a fileword\n" | PRIVATE_TERMS= PRIVATE_TERMS_FILE="$2" "$1" text body' _ "$CHECK" "$TMP/terms"
  [ "$status" -eq 1 ]
}

@test "range: added lines and messages are caught, removed lines are not" {
  mkrepo o/r
  printf 'secretword\n' >"$REPO/old.txt"
  git -C "$REPO" add old.txt && commit -m "add old"
  base=$(git -C "$REPO" rev-parse HEAD)
  git -C "$REPO" rm -q old.txt
  printf 'one\ntwo\nhidden place\n' >"$REPO/new.txt"
  git -C "$REPO" add new.txt && commit -m "chore: tidy" -m "for the secretword"
  run bash -c 'cd "$1" && "$2" range "$3..HEAD"' _ "$REPO" "$CHECK" "$base"
  [ "$status" -eq 1 ]
  [[ "$output" == *"new.txt:3: matches"* ]]
  [[ "$output" == *"message line 3: matches \"secretword\""* ]]
  [[ "$output" != *old.txt* ]]
}

@test "pre-push: a public remote is scanned, a private one is not" {
  mkrepo o/pub
  printf 'secretword\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt && commit -m "add a"
  sha=$(git -C "$REPO" rev-parse HEAD)
  visibility o pub public
  run bash -c 'cd "$1" && echo "refs/heads/x $3 refs/heads/x 0000000000000000000000000000000000000000" |
    "$2" pre-push origin https://github.com/o/pub.git' _ "$REPO" "$CHECK" "$sha"
  [ "$status" -eq 1 ]
  visibility o priv private
  run bash -c 'cd "$1" && echo "refs/heads/x $3 refs/heads/x 0000000000000000000000000000000000000000" |
    "$2" pre-push origin git@github.com:o/priv.git' _ "$REPO" "$CHECK" "$sha"
  [ "$status" -eq 0 ]
}

@test "claude-hook: git add && git commit to a public repo is blocked" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  bash_hook "git add a.txt && git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *'matches "secretword"'* ]]
}

@test "claude-hook: a staged change is scanned, not only untracked files" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt
  bash_hook "git commit -m x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"change to commit"* ]]
}

@test "claude-hook: a word in the commit message itself is blocked" {
  mkrepo o/pub
  visibility o pub public
  bash_hook "git commit -m \"for the hidden place\""
  [ "$status" -eq 2 ]
}

@test "claude-hook: the same commit to a private repo goes through" {
  mkrepo o/priv
  visibility o priv private
  printf 'secretword\n' >"$REPO/a.txt"
  bash_hook "git add a.txt && git commit -m x"
  [ "$status" -eq 0 ]
}

@test "claude-hook: git push carries unpushed commits through the scan" {
  mkrepo o/pub
  visibility o pub public
  printf 'secretword\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt && commit -m "add a"
  bash_hook "git push -u origin x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"a.txt:1"* ]]
}

@test "claude-hook: gh pr create --body-file is read" {
  mkrepo o/pub
  visibility o pub public
  printf 'Summary\n\nsecretword\n' >"$TMP/body.md"
  bash_hook "gh pr create --title t --body-file $TMP/body.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"body.md line 3"* ]]
}

@test "claude-hook: a GitHub MCP write to a public repo is blocked, a read is not" {
  visibility o pub public
  hook '{"tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"o","repo":"pub","body":"secretword"}}'
  [ "$status" -eq 2 ]
  hook '{"tool_name":"mcp__github__search_code","tool_input":{"owner":"o","repo":"pub","query":"secretword"}}'
  [ "$status" -eq 0 ]
  visibility o priv private
  hook '{"tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"o","repo":"priv","body":"secretword"}}'
  [ "$status" -eq 0 ]
}

@test "claude-hook: other Bash commands are left alone" {
  mkrepo o/pub
  visibility o pub public
  bash_hook "grep secretword notes.txt"
  [ "$status" -eq 0 ]
}

@test "install and cloud settings register the hook for Bash and GitHub MCP calls" {
  mkdir -p "$HOME/.claude"
  printf '{}\n' >"$HOME/.claude/settings.json"
  run "$REPO_ROOT/bin/install_claude_secret_scan_hook.sh"
  [ "$status" -eq 0 ]
  for f in "$HOME/.claude/settings.json" "$REPO_ROOT/claudecode/settings-cloud.json"; do
    jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|mcp__.*github.*")
      | .hooks[].command | contains("check_private_terms.sh\" claude-hook")' "$f" >/dev/null
  done
  run "$REPO_ROOT/bin/install_claude_secret_scan_hook.sh" --uninstall
  jq -e '.hooks.PreToolUse == null' "$HOME/.claude/settings.json" >/dev/null
}
