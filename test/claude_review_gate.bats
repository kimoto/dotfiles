#!/usr/bin/env bats

# Tests for bin/claude_review_gate.sh: a push carrying unreviewed commits is
# stopped once for a code review, commits after a mark are stopped again at the
# next push, and the first PR create on a branch is stopped once for its text.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  unset CLAUDE_CODE_REMOTE
  GATE="$REPO_ROOT/bin/claude_review_gate.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_review_gate.sh"
  SKILL="$REPO_ROOT/claudecode/skills/review-branch/SKILL.md"
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
  [[ "$r" == *"the review-branch skill ($SKILL)"* ]]
  [[ "$r" == *"\`$GATE mark $REPO s1\`"* ]]
  [[ "$r" == *"push again"* ]]
}

@test "the review-branch skill names every reviewer, and each exists as pinned" {
  full=$(sed -n '/^## 全体のレビュー/,/^## 終わったら/p' "$SKILL")
  # Codex is added beside correctness, never instead of it.
  grep -q '^1\. \*\*正しさ\*\*: `review-correctness` agent。$' <<<"$full"
  grep -q '^2\. \*\*Codex\*\*: .*codex-companion.mjs review --base' <<<"$full"
  # Without Codex, a second correctness reviewer that reads differently takes its place.
  grep -q '^2\. \*\*Codex\*\*: .*無い環境では、代わりに `review-correctness-checklist` agent。' <<<"$full"
  grep -q '`review-rules` agent' <<<"$full"
  grep -q 'codex-companion.mjs review --base' <<<"$full"
  # A subagent has no Agent tool, so the caller starts every reviewer itself, in one
  # message, and reads the findings only once every report is in.
  body=$(sed 1d <<<"$full")
  grep -q '1つのメッセージ' <<<"$body"
  grep -q 'Agent tool が無い' <<<"$body"
  grep -q 'そろうまで' <<<"$body"
  # The caller cannot choose how reports arrive, so the skill does not promise it.
  [ -z "$(grep 'まとめて届く' <<<"$body")" ]
  # Codex runs in Bash, whose foreground timeout a whole-branch review can outlast.
  grep -q '^2\. \*\*Codex\*\*: `run_in_background` で' <<<"$body"
  [ -z "$(grep 'まとめ役' "$SKILL")" ]
  grep -q 'どの係が出したか' <<<"$full"
  grep -q '推論を渡さない\|推論を渡すと' "$SKILL"
  grep -q '却下した理由は渡さない' "$SKILL"
  for pair in review-refactor:refactor-sweep review-tests:test-sweep review-security:security-audit \
    review-speed:bottleneck-sweep; do
    agent=${pair%%:*} sweep=${pair#*:}
    grep -q "\`$agent\`" <<<"$full"
    want=$(sed -n '2,/^---$/s/^model: //p' "$REPO_ROOT/claudecode/agents/$agent.md")
    grep -q "${agent#review-} → $sweep（$want）" <<<"$full"
    grep -q "skills/$sweep/SKILL.md" "$REPO_ROOT/claudecode/agents/$agent.md"
    grep -q '^## 差分モード' "$REPO_ROOT/claudecode/skills/$sweep/SKILL.md"
  done
  grep -q '`review-portability` agent' <<<"$full"
  # A reviewer with no sweep still has a fallback where its agent is unlinked.
  grep -q 'sweep の無い correctness・correctness-checklist・rules・portability は.*dotfiles の `claudecode/agents/<名前>.md`' \
    <<<"$full"
  for agent in review-correctness review-correctness-checklist review-rules review-portability review-refactor \
    review-tests review-security review-speed; do
    want=sonnet
    case $agent in review-security | review-correctness) want=opus ;; esac
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx "model: $want"
    tools='Read, Grep, Glob, Bash'
    # The correctness reviewer runs the bundled /code-review, so it needs Skill.
    [ "$agent" != review-correctness ] || tools="$tools, Skill"
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx "tools: $tools"
    # Pinned, not inherited from whatever the calling session runs at.
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx 'effort: medium'
  done
  for agent in review-correctness review-correctness-checklist review-portability review-refactor review-tests \
    review-security review-speed; do
    sed -n '2,/^---$/p' "$REPO_ROOT/claudecode/agents/$agent.md" | grep -qx 'omitClaudeMd: true'
  done
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
  [[ "$(reason)" == *"\`$GATE mark $REPO s1\`"* ]]
}

@test "a machine that has linked the skill is pointed at its linked copy" {
  mkdir -p "$HOME/.claude/skills"
  ln -s "$REPO_ROOT/claudecode/skills/review-branch" "$HOME/.claude/skills/review-branch"
  pre_bash "git push"
  [[ "$(reason)" == *"the review-branch skill ($HOME/.claude/skills/review-branch/SKILL.md)"* ]]
}

@test "commits after the mark are stopped at the next push, named from the mark" {
  "$GATE" mark "$REPO" s1
  marked="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" commit -q --allow-empty -m fix
  pre_bash "git push"
  [ "$(decision)" = deny ]
  r="$(reason)"
  [[ "$r" == *"1 commit(s) on feat/x that no review has seen"* ]]
  [[ "$r" == *"log $marked..feat/x --not --remotes"* ]]
  [[ "$r" == *"\`$GATE mark $REPO s1\`"* ]]
  # How widely to look is the agent's call, and the skill says so.
  grep -q '最終的な差分を通しで' "$SKILL"
}

@test "new commits are stopped however many marks came before" {
  for n in 1 2 3; do
    "$GATE" mark "$REPO" s1
    git -C "$REPO" commit -q --allow-empty -m "c$n"
    pre_bash "git push"
    [ "$(decision)" = deny ]
  done
}

@test "a branch name with shell syntax is quoted in the command to paste" {
  git -C "$REPO" switch -q -c 'x$(id)'
  pre_bash "git push"
  [[ "$(reason)" == *'log x\$\(id\) --not --remotes'* ]]
}

@test "a mark without a session survives a mark made in another repo" {
  "$GATE" mark "$REPO"
  git init -q -b main "$TMP/third"
  git -C "$TMP/third" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  (cd "$TMP/third" && "$GATE" mark "$TMP/third" s1)
  pre_bash "git push"
  [ -z "$output" ]
}

@test "a repo path with a quote is quoted in the commands to paste" {
  q="$TMP/it's"
  git init -q -b main "$q"
  git -C "$q" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  pre_bash "git push" "$q"
  r="$(reason)"
  [[ "$r" == *"git -C $(printf '%q' "$q") log main"* ]]
  [[ "$r" == *"mark $(printf '%q' "$q") s1"* ]]
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
  [[ "$r" == *"title and body"* ]]
  [[ "$r" == *"under PR の題と本文"* ]]
  grep -q '^## PR の題と本文' "$SKILL"
  sed -n '/^## PR の題と本文/,$p' "$SKILL" | grep -q '`review-rules` agent'
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
  [[ "$(ls "$XDG_STATE_HOME/claude-review")" == main@* ]]
  [ "$(ls "$XDG_STATE_HOME/claude-review" | wc -l | tr -d ' ')" = 1 ]
}

@test "the same branch name in two repos keeps two marks" {
  git init -q -b main "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$REPO" switch -q main
  "$GATE" mark "$REPO" s1
  "$GATE" mark "$TMP/other" s1
  pre_bash "git push"
  [ -z "$output" ]
}

@test "a PR text check is asked again for a reused branch name elsewhere" {
  pre_bash "gh pr create --fill"
  [ "$(decision)" = deny ]
  git init -q -b feat/x "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  pre_bash "gh pr create --fill" "$TMP/other"
  [ "$(decision)" = deny ]
}

@test "commits pulled in after the mark are not counted" {
  with_remote feat/x
  "$GATE" mark "$REPO" s1
  git clone -q -b feat/x "$TMP/remote.git" "$TMP/peer"
  git -C "$TMP/peer" -c user.name=p -c user.email=p@example.com commit -q --allow-empty -m theirs
  git -C "$TMP/peer" push -q origin feat/x
  git -C "$REPO" pull -q --ff-only origin feat/x
  pre_bash "git push"
  [ -z "$output" ]
}

@test "a push naming another branch is judged by that branch" {
  git -C "$REPO" switch -q main
  "$GATE" mark "$REPO" s1
  pre_bash "git push origin feat/x"
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"on feat/x"* ]]
}

@test "a push that carries no commits passes" {
  pre_bash "git push origin --delete old"
  [ -z "$output" ]
  pre_bash "git push --tags"
  [ -z "$output" ]
}

@test "cd before the push and an env prefix are followed" {
  pre_bash "cd '$REPO' && git push" "$TMP"
  [ "$(decision)" = deny ]
  git -C "$REPO" commit -q --allow-empty -m more
  pre_bash "GIT_TRACE=0 git push"
  [ "$(decision)" = deny ]
}

@test "only a cd before the push counts, and ~ is expanded" {
  pre_bash "git push origin feat/x && cd /tmp"
  [ "$(decision)" = deny ]
  git -C "$REPO" commit -q --allow-empty -m more
  pre_bash "cd ~/../repo && git push" "$TMP"
  [ "$(decision)" = deny ]
  git -C "$REPO" commit -q --allow-empty -m again
  pre_bash "(cd /tmp && ls); git push"
  [ "$(decision)" = deny ]
}

@test "option values and full ref names do not hide the pushed branch" {
  git -C "$REPO" switch -q main
  "$GATE" mark "$REPO" s1
  pre_bash "git push -o ci.skip origin feat/x"
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"on feat/x"* ]]
  rm -rf "$XDG_STATE_HOME/claude-review-pushed"
  pre_bash "git push origin refs/heads/feat/x"
  [ "$(decision)" = deny ]
  rm -rf "$XDG_STATE_HOME/claude-review-pushed"
  pre_bash "git push origin main feat/x"
  [ "$(decision)" = deny ]
}

@test "a push that passes still lets a PR create on the same line be asked" {
  "$GATE" mark "$REPO" s1
  pre_bash "git push -u origin feat/x && gh pr create --fill"
  [ "$(decision)" = deny ]
  [[ "$(reason)" == *"title and body"* ]]
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
  run jq -e '.hooks.Stop[]?.hooks[].command | select(contains("claude_review_gate.sh"))' "$SETTINGS"
  [ "$status" -ne 0 ]
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
