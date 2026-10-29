#!/usr/bin/env bats

# Tests for bin/claude_review_gate.sh: the first PR create on a branch is
# stopped until its review is marked done, and a session that stops with
# commits after the last mark is sent back to re-check them.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  unset CLAUDE_CODE_REMOTE
  GATE="$REPO_ROOT/bin/claude_review_gate.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_review_gate.sh"
  TMP="$(mktemp -d)"
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

stop() {
  run_payload "$(jq -cn --arg s "${1:-s1}" --argjson a "${2:-false}" \
    '{hook_event_name: "Stop", session_id: $s, cwd: "/", stop_hook_active: $a}')"
}

reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // .reason' <<<"$output"; }

@test "other Bash commands pass silently" {
  pre_bash "git status"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  pre_bash "grep -n 'gh pr create' notes.md"
  [ -z "$output" ]
}

@test "the first gh pr create on a branch is denied with the review to run" {
  pre_bash "gh pr create --fill"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]
  r="$(reason)"
  [[ "$r" == *"review-correctness"* ]]
  [[ "$r" == *"review-rules"* ]]
  for sweep in refactor-sweep test-sweep security-audit bottleneck-sweep; do
    [[ "$r" == *"skills/$sweep/SKILL.md"* ]]
    grep -q '^## 差分モード' "$REPO_ROOT/claudecode/skills/$sweep/SKILL.md"
  done
  [ -f "$REPO_ROOT/claudecode/agents/review-correctness.md" ]
  [ -f "$REPO_ROOT/claudecode/agents/review-rules.md" ]
  [[ "$r" == *"run_in_background"* ]]
  [[ "$r" == *"not your reasoning"* ]]
  [[ "$r" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
}

@test "once marked, the create goes through" {
  "$GATE" mark "$REPO" s1
  pre_bash "gh pr create --fill"
  [ -z "$output" ]
}

@test "a create through the MCP tool is gated on its head branch" {
  pre_mcp feat/x
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]
  "$GATE" mark "$REPO" s1
  pre_mcp feat/x
  [ -z "$output" ]
  pre_mcp feat/other
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]
}

@test "gh pr create --head names the branch, wherever the session stands" {
  "$GATE" mark "$REPO" s1
  pre_bash "gh pr create --head feat/x --fill" "$TMP"
  [ -z "$output" ]
  pre_bash "gh pr create -H feat/other --fill" "$TMP"
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]
}

@test "with Codex enabled, Codex takes correctness" {
  mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts"
  touch "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts/codex-companion.mjs"
  jq -n '{enabledPlugins: {"codex@openai-codex": true}}' >"$SETTINGS"
  pre_bash "gh pr create --fill"
  [[ "$(reason)" == *"codex-companion.mjs\" review --base"* ]]
  [[ "$(reason)" != *"review-correctness"* ]]
  CLAUDE_CODE_REMOTE=true pre_bash "gh pr create --fill"
  [[ "$(reason)" == *"review-correctness"* ]]
}

@test "stopping with commits after the mark sends the session back to re-check them" {
  "$GATE" mark "$REPO" s1
  marked="$(git -C "$REPO" rev-parse HEAD)"
  stop
  [ -z "$output" ]
  git -C "$REPO" commit -q --allow-empty -m more
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
  r="$(reason)"
  [[ "$r" == *"$marked..feat/x"* ]]
  [[ "$r" == *"earlier findings"* ]]
  [[ "$r" == *"not why you dismissed"* ]]
  [[ "$r" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
}

@test "the re-check stops after two rounds, and never blocks twice in a row" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  stop s1 true
  [ -z "$output" ]
  stop s2
  [ -z "$output" ]
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m again
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m last
  stop
  [ -z "$output" ]
}

@test "a re-check is asked once per new commit, not at every stop while it runs" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
  [[ "$(reason)" == *"\`'$GATE' mark '$REPO' s1\`"* ]]
  stop
  [ -z "$output" ]
  git -C "$REPO" commit -q --allow-empty -m again
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
}

@test "an ask left unanswered is repeated once the reviewer would have finished" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
  f="$XDG_STATE_HOME/claude-review-asked/feat%x"
  read -r sha _ <"$f"
  printf '%s %s\n' "$sha" "$(($(date +%s) - 601))" >"$f"
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
}

@test "a branch named like the ask store still gets its re-check" {
  git -C "$REPO" switch -q -c asked
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  stop
  [ "$(jq -r '.decision' <<<"$output")" = block ]
}

@test "a deleted branch drops its mark" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" switch -q main
  git -C "$REPO" branch -q -D feat/x
  stop
  [ -z "$output" ]
  [ -z "$(ls "$XDG_STATE_HOME/claude-review")" ]
}

@test "a deleted branch drops its ask too" {
  "$GATE" mark "$REPO" s1
  git -C "$REPO" commit -q --allow-empty -m more
  stop
  [ -n "$(ls "$XDG_STATE_HOME/claude-review-asked")" ]
  git -C "$REPO" switch -q main
  git -C "$REPO" branch -q -D feat/x
  stop
  [ -z "$(ls "$XDG_STATE_HOME/claude-review-asked")" ]
}

@test "install registers the gate before PR creation and on Stop, and uninstall removes it" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash|mcp__.*__create_pull_request")
    | .hooks[].command | select(contains("claude_review_gate.sh"))' "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop[].hooks[].command | select(contains("claude_review_gate.sh"))' "$SETTINGS" >/dev/null
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
  jq -e '.hooks.Stop[].hooks[].command | select(contains("claude_review_gate.sh"))' \
    "$REPO_ROOT/claudecode/settings-cloud.json" >/dev/null
}
