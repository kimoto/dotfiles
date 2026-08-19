#!/usr/bin/env bats

# Tests for .claude/hooks/pr-description-reminder.sh, the PostToolUse hook that
# nudges an agent to refresh the PR description after a push. The hook reads
# Claude Code's tool-call JSON on stdin and answers with hookSpecificOutput
# JSON — or with nothing at all, which is the case that matters: a command that
# merely mentions a push (a grep pattern, an echo) must not fire it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  HOOK="$REPO_ROOT/.claude/hooks/pr-description-reminder.sh"
}

# Feed one command through the hook the way Claude Code does.
run_hook() {
  run bash -c "printf '%s' \"\$1\" | '$HOOK'" _ "$(jq -cn --arg c "$1" '{tool_input: {command: $c}}')"
}

@test "a plain git push asks for the PR description update" {
  run_hook "git push"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PostToolUse" ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"pull request"* ]]
}

@test "fires for a push with flags, a remote, and a leading command" {
  for cmd in "git push -u origin feat/thing --force-with-lease" \
             "git -C /tmp/repo push" \
             "./bin/lint_shell.sh && git push"; do
    run_hook "$cmd"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PostToolUse" ]
  done
}

@test "stays silent when the push is only quoted text" {
  run_hook "grep -n 'git push' AGENTS.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_hook "echo \"git push\""
  [ -z "$output" ]
}

@test "stays silent for other git commands" {
  run_hook "git status"
  [ -z "$output" ]
  run_hook "git log --oneline -5"
  [ -z "$output" ]
}

@test "survives a payload with no command at all" {
  run bash -c "printf '%s' '{}' | '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits valid JSON, so Claude Code can parse it" {
  run_hook "git push"
  echo "$output" | jq empty
}
