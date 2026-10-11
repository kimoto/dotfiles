#!/usr/bin/env bats

# Tests for .claude/hooks/worktree-guard.sh, the PreToolUse hook that refuses a
# worktree made from Bash and sends the agent to EnterWorktree. The hook reads
# Claude Code's tool-call JSON on stdin and answers with a deny decision — or
# with nothing, which lets the call through and must stay the answer for every
# command that only mentions a worktree.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  HOOK="$REPO_ROOT/.claude/hooks/worktree-guard.sh"
}

# Feed one command through the hook the way Claude Code does.
run_hook() {
  run bash -c "printf '%s' \"\$1\" | '$HOOK'" _ "$(jq -cn --arg c "$1" '{tool_input: {command: $c}}')"
}

denied() {
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *EnterWorktree* ]]
}

@test "refuses git worktree add, however it is spelled" {
  for cmd in "git worktree add ../x -b feat/x" \
             "git -C /tmp/repo worktree add /tmp/wt" \
             "git fetch -q origin && git worktree add -q -b chore/x ../x origin/main && cd ../x"; do
    run_hook "$cmd"
    denied
  done
}

@test "refuses the W helper's script, by path or by name" {
  for cmd in "./bin/worktree_new.sh feat/x" \
             "cd \"\$(worktree_new.sh feat/x)\"" \
             "\$HOME/bin/worktree_new.sh fix/y"; do
    run_hook "$cmd"
    denied
  done
}

@test "lets other worktree commands through" {
  for cmd in "git worktree list" "git worktree remove ../x" "git worktree prune"; do
    run_hook "$cmd"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "lets a command that only mentions it through" {
  for cmd in "grep -n 'git worktree add' AGENTS.md" \
             "echo \"git worktree add\"" \
             "sed -n 1,40p bin/worktree_new.sh"; do
    run_hook "$cmd"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "survives a payload with no command at all" {
  run bash -c "printf '%s' '{}' | '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
