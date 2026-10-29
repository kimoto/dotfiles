#!/usr/bin/env bats

# Tests for bin/claude_review_gate.sh: a push carrying unreviewed commits is
# stopped once for a code review, commits after a mark are re-checked at the
# next push, and the first PR create on a branch is stopped once for its text.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  unset CLAUDE_CODE_REMOTE
  GATE="$REPO_ROOT/bin/claude_review_gate.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_review_gate.sh"
  # Resolved, so paths match what git prints (macOS mktemp gives /var, git /private/var).
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.claude/settings.json"
  REPO="$TMP/repo"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" commit -q --allow-empty -m init
  git -C "$REPO" switch -q -c feat/x
  git -C "$REPO" commit -q --allow-empty -m work
}

teardown() {
  rm -rf "$TMP"
}

run_payload() {
  run bash -c "printf '%s' \"\$1\" | '$GATE'" _ "$1"
}

pre_bash() {
  run_payload "$(jq -cn --arg c "$1" --arg d "${2:-$REPO}" \
    '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash", tool_input: {command: $c}}')"
}

pre_mcp() {
  run_payload "$(jq -cn --arg h "$1" --arg d "$TMP" \
    '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "mcp__github__create_pull_request",
      tool_input: {owner: "o", repo: "r", head: $h, base: "main", title: "t"}}')"
}

decision() { jq -r '.hookSpecificOutput.permissionDecision' <<<"$output"; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output"; }

with_remote() {
  git init -q --bare "$TMP/remote.git"
  git -C "$REPO" remote add origin "$TMP/remote.git"
  git -C "$REPO" push -q origin "$@"
}

@test "other Bash commands pass silently" {
  pre_bash "git status"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  pre_bash "grep -n 'gh pr create' notes.md"
  [ -z "$output" ]
  pre_bash "echo 'git push'"
  [ -z "$output" ]
}

@test "a first push of unreviewed commits is denied with the review to run" {
  pre_bash "git push -u origin feat/x"
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  r="$(reason)"
  [[ "$r" == *"publishes 2 commit(s) on feat/x"* ]]
  [[ "$r" == *"review-correctness"* ]]
  [[ "$r" == *"review-rules subagent, for the commit messages"* ]]
  for pair in review-refactor:refactor-sweep review-tests:test-sweep review-security:security-audit \
    review-speed:bottleneck-sweep; do
    agent=${pair%%:*} sweep=${pair#*:}
    want=sonnet
    [ "$agent" != review-security ] || want=opus
    [[ "$r" == *"skills/$sweep/SKILL.md and follows its diff mode (差分モード), with model: $want;"* || \
      "$r" == *"skills/$sweep/SKILL.md and follows its diff mode (差分モード), with model: $want."* ]]
    grep -q "skills/$sweep/SKILL.md" "$REPO_ROOT/claudecode/agents/$agent.md"
    grep -q '^## 差分モード' "$REPO_ROOT/claudecode/skills/$sweep/SKILL.md"
  done
  [[ "$r" == *"run_in_background"* ]]
  for agent in review-correctness review-rules review-refactor review-tests review-security review-speed; do
    want=sonnet
    [ "$agent" != review-security ] || want=opus
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx "model: $want"
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx 'tools: Read, Grep, Glob, Bash'
  done
  for agent in review-correctness review-refactor review-tests review-security review-speed; do
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx 'omitClaudeMd: true'
  done
  [[ "$r" == *"not your reasoning"* ]]
  [[ "$r" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
  [[ "$r" == *"push again"* ]]
}

@test "the same HEAD is stopped once; a new commit is stopped again" {
  pre_bash "git push"
  [ "$(decision)" = deny ]
  pre_bash "git push"
  [ -z "$output" ]
  git -C "$REPO" commit -q --allow-empty -m more
  pre_bash "git push"
  [ "$(decision)" = deny ]
}

@test "a direct push to main is stopped the same way" {
  git -C "$REPO" switch -q main
  git -C "$REPO" commit -q --allow-empty -m direct
  pre_bash "git push origin main"
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"on main"* ]]
}

@test "a reviewed HEAD, or nothing unpublished, pushes silently" {
  "$GATE" mark "$REPO" s1
  pre_bash "git push"
  [ -z "$output" ]
  git -C "$REPO" switch -q main
  with_remote main
  pre_bash "git push"
  [ -z "$output" ]
}

@test "git -C names the repo, wherever the session stands" {
  pre_bash "git -C '$REPO' push" "$TMP"
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
}

@test "a reviewer agent this machine has linked is named; one it lacks falls back to its skill" {
  mkdir -p "$HOME/.claude/agents"
  ln -s "$REPO_ROOT/claudecode/agents/review-security.md" "$HOME/.claude/agents/review-security.md"
  pre_bash "git push"
  r="$(reason)"
  [[ "$r" == *"the review-security subagent"* ]]
  [[ "$r" != *"skills/security-audit/SKILL.md"* ]]
  [[ "$r" == *"skills/test-sweep/SKILL.md and follows its diff mode (差分モード), with model: sonnet"* ]]
}

@test "with Codex enabled, Codex takes correctness" {
  mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts"
  touch "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts/codex-companion.mjs"
  jq -n '{enabledPlugins: {"codex@openai-codex": true}}' >"$SETTINGS"
  pre_bash "git push"
  [[ "$(reason)" == *"codex-companion.mjs\" review --base"* ]]
  [[ "$(reason)" != *"review-correctness"* ]]
  git -C "$REPO" commit -q --allow-empty -m more
  CLAUDE_CODE_REMOTE=true pre_bash "git push"
  [[ "$(reason)" == *"review-correctness"* ]]
}

@test "commits after the mark are re-checked at the next push, with the earlier findings" {
  "$GATE" mark "$REPO" s1
  marked="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" commit -q --allow-empty -m fix
  pre_bash "git push"
  [ "$(decision)" = deny ]
  r="$(reason)"
  [[ "$r" == *"$marked..feat/x"* ]]
  [[ "$r" == *"earlier findings"* ]]
  [[ "$r" == *"not why you dismissed"* ]]
  [[ "$r" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
}

@test "the re-check stops after two rounds" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m one
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m two
  pre_bash "git push"
  [ "$(decision)" = deny ]
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m three
  pre_bash "git push"
  [ -z "$output" ]
}

@test "a mark left behind by a rebase gives a full review again" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --amend --allow-empty -m reworded
  pre_bash "git push"
  [[ "$(reason)" == *"no review has seen"* ]]
}

@test "the first gh pr create on a branch is denied once, for its text" {
  pre_bash "gh pr create --fill"
  [ "$(decision)" = deny ]
  r="$(reason)"
  [[ "$r" == *"review-rules"* ]]
  [[ "$r" == *"title and body"* ]]
  [[ "$r" != *"review-correctness"* ]]
  pre_bash "gh pr create --fill"
  [ -z "$output" ]
}

@test "a create through the MCP tool is asked on its head branch" {
  pre_mcp feat/x
  [ "$(decision)" = deny ]
  pre_mcp feat/x
  [ -z "$output" ]
  pre_mcp feat/other
  [ "$(decision)" = deny ]
}

@test "gh pr create --head names the branch, wherever the session stands" {
  pre_bash "gh pr create --head feat/x --fill" "$TMP"
  [ "$(decision)" = deny ]
  pre_bash "gh pr create --head feat/x --fill" "$TMP"
  [ -z "$output" ]
  pre_bash "gh pr create -H feat/other --fill" "$TMP"
  [ "$(decision)" = deny ]
}

@test "a branch named like a sibling store keeps its own mark" {
  git -C "$REPO" switch -q -c pushed
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  pre_bash "git push"
  [ "$(decision)" = deny ]
}

@test "a mark of a deleted branch is dropped at the next mark" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" switch -q main
  git -C "$REPO" branch -q -D feat/x
  "$GATE" mark "$REPO" s1
  [ "$(ls "$XDG_STATE_HOME/claude-review")" = main ]
}

@test "a Stop no longer does anything" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  run_payload '{"hook_event_name": "Stop", "session_id": "s1", "cwd": "/", "stop_hook_active": false}'
  [ -z "$output" ]
}

@test "install registers the gate before push and PR creation only, and uninstall removes it" {
  jq -n '{hooks: {Stop: [{matcher: "", hooks: [{type: "command",
    command: "[ ! -x \"$HOME/bin/claude_review_gate.sh\" ] || \"$HOME/bin/claude_review_gate.sh\""}]}]}}' \
    >"$TMP/old.json"
  mkdir -p "$HOME/.claude"
  cp "$TMP/old.json" "$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|mcp__.*__create_pull_request")
    | .hooks[].command | select(contains("claude_review_gate.sh"))' "$SETTINGS" >/dev/null
  ! jq -e '.hooks.Stop[]?.hooks[].command | select(contains("claude_review_gate.sh"))' "$SETTINGS" >/dev/null
  first="$(cat "$SETTINGS")"
  "$INSTALLER"
  [ "$(cat "$SETTINGS")" = "$first" ]
  "$INSTALLER" --uninstall
  ! grep -q claude_review_gate.sh "$SETTINGS"
}

@test "the cloud settings run the same gate on the same events" {
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|mcp__.*__create_pull_request")
    | .hooks[].command | select(contains("claude_review_gate.sh"))' \
    "$REPO_ROOT/claudecode/settings-cloud.json" >/dev/null
  ! jq -e '.hooks.Stop[]?.hooks[].command | select(contains("claude_review_gate.sh"))' \
    "$REPO_ROOT/claudecode/settings-cloud.json" >/dev/null
}
