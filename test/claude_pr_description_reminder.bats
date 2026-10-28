#!/usr/bin/env bats

# Tests for bin/claude_pr_description_reminder.sh, the PostToolUse hook that
# nudges an agent to re-check the PR description after a push. The hook reads
# Claude Code's tool-call JSON on stdin and answers with hookSpecificOutput
# JSON — or with nothing at all, which is the case that matters: a command that
# merely mentions a push (a grep pattern, an echo) must not fire it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  # The hook stays quieter in a cloud session; a test run from one inherits
  # that, so each test starts local and the cloud cases set it themselves.
  unset CLAUDE_CODE_REMOTE
  HOOK="$REPO_ROOT/bin/claude_pr_description_reminder.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_pr_hooks.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() {
  rm -rf "$TMP"
}

# Feed one command through the hook the way Claude Code does.
run_hook() {
  run bash -c "printf '%s' \"\$1\" | '$HOOK'" _ "$(jq -cn --arg c "$1" '{tool_input: {command: $c}}')"
}

# Same, with what the command printed, as Claude Code passes it back.
run_hook_with_stdout() {
  run bash -c "printf '%s' \"\$1\" | '$HOOK'" _ \
    "$(jq -cn --arg c "$1" --arg o "$2" '{tool_input: {command: $c}, tool_response: {stdout: $o}}')"
}

PR_URL="https://github.com/kimoto/dotfiles/pull/541"

@test "a created PR asks for the watcher, naming its URL" {
  run_hook_with_stdout "gh pr create --title t --body-file -" "$PR_URL"
  [ "$status" -eq 0 ]
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"~/bin/watch_pr.sh $PR_URL"* ]]
  [[ "$ctx" == *"run_in_background"* ]]
}

@test "a cloud session, which has its own PR subscription, gets no watcher" {
  CLAUDE_CODE_REMOTE=true run_hook_with_stdout "gh pr create --fill" "$PR_URL"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  CLAUDE_CODE_REMOTE=true run_hook_with_stdout "git push && gh pr create --fill" "$PR_URL"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"pull-requests.md"* ]]
  [[ "$ctx" != *"watch_pr.sh"* ]]
}

# Install the Codex plugin under $HOME the way Claude Code lays it out, and
# set whether settings.json has it enabled.
codex_plugin() {
  local enabled=$1
  for v in 1.0.6 1.0.10; do
    mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/$v/scripts"
    touch "$HOME/.claude/plugins/cache/openai-codex/codex/$v/scripts/codex-companion.mjs"
  done
  jq -n --argjson e "$enabled" '{enabledPlugins: {"codex@openai-codex": $e}}' >"$HOME/.claude/settings.json"
}

@test "a push with the Codex plugin enabled asks for its review, newest version" {
  codex_plugin true
  run_hook "git push"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"pull-requests.md"* ]]
  [[ "$ctx" == *"codex/1.0.10/scripts/codex-companion.mjs\" review --base"* ]]
  [[ "$ctx" == *"run_in_background"* ]]
}

@test "no Codex review when the plugin is disabled, missing, or in a cloud session" {
  codex_plugin false
  run_hook "git push"
  [[ "$output" != *"codex"* ]]
  rm -rf "$HOME/.claude"
  run_hook "git push"
  [[ "$output" != *"codex"* ]]
  codex_plugin true
  CLAUDE_CODE_REMOTE=true run_hook "git push"
  [[ "$output" != *"codex"* ]]
  run_hook "git status"
  [ -z "$output" ]
}

@test "without Codex, a push asks for a fresh-context subagent review instead" {
  run_hook "git push"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"subagent"* ]]
  [[ "$ctx" == *"two review rounds"* ]]
  CLAUDE_CODE_REMOTE=true run_hook "git push"
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"subagent"* ]]
  codex_plugin true
  run_hook "git push"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"codex-companion.mjs"* ]]
  [[ "$ctx" == *"two review rounds"* ]]
}

@test "a push asks for a separate performance reviewer beside the correctness one" {
  run_hook "git push"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"correctness bugs"* ]]
  [[ "$ctx" == *"performance"* ]]
  codex_plugin true
  run_hook "git push"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"codex-companion.mjs"* ]]
  [[ "$ctx" == *"performance"* ]]
  [[ "$ctx" != *"correctness bugs"* ]]
}

ctx_of() { jq -r '.hookSpecificOutput.additionalContext' <<<"$output"; }

@test "a commit asks a fast subagent for a first look at that commit alone" {
  run_hook "git -C repo commit -am x"
  ctx="$(ctx_of)"
  [[ "$ctx" == *"haiku"* ]]
  [[ "$ctx" == *"HEAD~1..HEAD"* ]]
  [[ "$ctx" == *"run_in_background"* ]]
  CLAUDE_CODE_REMOTE=true run_hook "git commit -m x"
  [[ "$(ctx_of)" == *"haiku"* ]]
}

@test "a commit that records nothing, or a command that only names one, asks for no review" {
  run_hook "git commit --dry-run"
  [ -z "$output" ]
  run_hook "git log --grep 'git commit'"
  [ -z "$output" ]
}

@test "a push that publishes no new code asks for no review" {
  for c in "git push origin --delete feat/x" "git push -d origin feat/x" \
    "git push --dry-run" "git push -n origin HEAD" "git push --tags"; do
    run_hook "$c"
    ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
    [[ "$ctx" == *"pull-requests.md"* ]]
    [[ "$ctx" != *"review"* ]]
  done
  run_hook "git push -u origin feat/dry-run"
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"subagent"* ]]
}

@test "the watcher the reminder names exists where ~/bin points" {
  [ -x "$REPO_ROOT/bin/watch_pr.sh" ]
}

@test "a gh pr create that printed no PR URL stays silent" {
  run_hook_with_stdout "gh pr create --title t" "a pull request for branch already exists"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a quoted gh pr create stays silent even beside a PR URL" {
  run_hook_with_stdout "grep -n 'gh pr create --fill' notes.md" "$PR_URL"
  [ -z "$output" ]
}

@test "a push and a PR create in one command get both reminders" {
  run_hook_with_stdout "git push -u origin feat/x && gh pr create --fill" "$PR_URL"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"pull-requests.md"* ]]
  [[ "$ctx" == *"watch_pr.sh $PR_URL"* ]]
}

@test "a plain git push asks for the PR description update" {
  run_hook "git push"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PostToolUse" ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"pull request"* ]]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"rules/dotfiles/pull-requests.md"* ]]
}

@test "the rule the reminder points at exists where mklink.sh links it" {
  [ -f "$REPO_ROOT/claudecode/rules/pull-requests.md" ]
  grep -q 'rules/dotfiles' "$REPO_ROOT/bin/mklink.sh"
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

# Count the entries that run our handler, wherever they sit.
count_ours() {
  jq '[.hooks[][] | .hooks[]
     | select(.command | contains("claude_pr_description_reminder.sh"))] | length' "$SETTINGS"
}

@test "install registers the hook on Bash PostToolUse, guarded on ~/bin" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hooks.PostToolUse[0].matcher' "$SETTINGS")" = Bash ]
  cmd="$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$SETTINGS")"
  [[ "$cmd" == *'[ ! -x "$HOME/bin/claude_pr_description_reminder.sh" ]'* ]]
}

@test "the registered command runs the hook and stays quiet without ~/bin" {
  "$INSTALLER"
  cmd="$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$SETTINGS")"
  payload="$(jq -cn '{tool_input: {command: "git push"}}')"
  run sh -c "$cmd" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ln -s "$REPO_ROOT/bin" "$HOME/bin"
  run sh -c "$cmd" <<<"$payload"
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = PostToolUse ]
}

@test "rerunning changes nothing (no stacked duplicates)" {
  "$INSTALLER"
  first="$(cat "$SETTINGS")"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
  [ "$(count_ours)" -eq 1 ]
}

@test "--uninstall removes our hook and keeps other settings and hooks" {
  mkdir -p "$HOME/.claude"
  cat >"$SETTINGS" <<'JSON'
{"model":"opus","hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo other"}]}]}}
JSON
  "$INSTALLER"
  [ "$(count_ours)" -eq 1 ]
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "$SETTINGS")" = opus ]
  jq -e '.hooks.PostToolUse[].hooks[] | select(.command == "echo other")' "$SETTINGS" >/dev/null
  [ "$(count_ours)" -eq 0 ]
}

@test "leaves an invalid settings.json untouched and exits 0 (bootstrap-safe)" {
  mkdir -p "$HOME/.claude"
  printf 'not json' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}

@test "the cloud settings run the same handler on Bash PostToolUse" {
  jq -e '.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[].command
    | select(contains("claude_pr_description_reminder.sh"))' \
    "$REPO_ROOT/claudecode/settings-cloud.json" >/dev/null
}
