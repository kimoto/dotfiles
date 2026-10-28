#!/bin/bash
# Claude Code PostToolUse hook for Bash calls and for opening a PR through a
# GitHub MCP tool (registered in every repo by bin/install_claude_pr_hooks.sh,
# and by settings-cloud.json in a container): after a push, remind the agent
# that the PR description may no longer hold; after a PR is opened, have it
# reviewed once, and watched where no PR subscription exists.
#
# Claude Code sends the tool call as JSON on stdin and reads hookSpecificOutput
# JSON back on stdout; printing nothing means "no comment". Quoted text is
# stripped before matching, so a command that only mentions a push — a grep
# pattern, an echo — leaves the hook silent.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
# One jq for both fields: this runs after every Bash call.
{ IFS= read -r tool; IFS= read -r cmd; } < <(jq -r '(.tool_name // ""), (.tool_input.command // "" | gsub("\n"; "; "))' <<<"$payload" 2>/dev/null)
pr_url() {
  jq -r '.tool_response | tostring' <<<"$payload" 2>/dev/null \
    | grep -oE 'https://github\.com/[^/[:space:]"]+/[^/[:space:]"]+/pull/[0-9]+' | head -1
}

# Drop quoted strings, so only commands that actually ran are matched, at the
# start of a command in the line.
bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
starts='(^|[;&|(]|&&|\|\|)[[:space:]]*'

context=""
url=""
push_publishes_code=false

# git with any options (e.g. -C <dir>), then the push subcommand. What a
# description may hold lives in one place, the pull-requests rule every session
# already loads; the reminder only points there, so the two never drift.
if printf '%s' "$bare" | grep -qE "${starts}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+push([[:space:];&|)]|\$)"; then
  context="A git push just ran. If the pushed branch has an open pull request, re-check its title and body against ~/.claude/rules/dotfiles/pull-requests.md and fix what this push made untrue."
  # A delete (also as :branch), a dry run or tags alone publish no code.
  printf '%s' "$bare" | grep -qE "push[^;&|]*[[:space:]](--delete|-d|--dry-run|-n|--tags|:[^[:space:]]+)([[:space:];&|]|\$)" \
    || push_publishes_code=true
fi

# The URL in the response is the proof a PR exists; without one the create
# failed. A cloud session already hears its PRs, and may have no gh.
gh_create=false
printf '%s' "$bare" | grep -qE "${starts}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|\$)" && gh_create=true
if [[ "$tool" == *__create_pull_request ]] || [ "$gh_create" = true ]; then
  url=$(pr_url)
fi
if [ -n "$url" ] && [ "$gh_create" = true ] && [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  context="${context:+$context }A pull request was just created: $url. Unless this session can subscribe to PR activity, start \`~/bin/watch_pr.sh $url\` with run_in_background now, so its merge, close or failing check reaches you; re-arm it after you push a fix for a failed check."
fi

# Codex takes correctness where enabled: a different model.
companion=""
if { [ -n "$url" ] || [ "$push_publishes_code" = true ]; } && [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] \
  && jq -e '.enabledPlugins["codex@openai-codex"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  companion=$(printf '%s\n' "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs \
    | sort -V | tail -1)
fi
if [ -f "$companion" ]; then
  correctness="\`node \"$companion\" review --base <the PR's base>\`"
else
  correctness="the review-correctness subagent"
fi

# One full review when a PR opens, not per push: pushes are many. Each
# viewpoint is a sweep's own diff mode, so the review at open and the
# scheduled sweep look for the same things.
if [ -n "$url" ]; then
  context="${context:+$context }Review $url once now, after fetching its base. Reviewers only report; you fix and push to the same PR. Give each only the repo path, the PR's commits not on its base, and its stated purpose, not your reasoning. Start, all with run_in_background:"
  context="$context $correctness; the review-rules subagent, also given the PR URL;"
  for sweep in refactor-sweep test-sweep security-audit bottleneck-sweep; do
    context="$context a subagent that reads ~/.claude/skills/$sweep/SKILL.md and follows its diff mode (差分モード);"
  done
  context="${context%;}. When they return, fix what holds up and say which findings you dismissed. On a public repo, keep security findings out of the PR text."
fi

# After the review at open, a push brings only what changed since: correctness
# on those commits, checked against the earlier findings, is enough. Two
# rounds stop review and fix from looping.
if [ "$push_publishes_code" = true ] && [ -z "$url" ]; then
  context="${context:+$context }If that PR was reviewed when it was opened, review the commits pushed since the last review with $correctness, run_in_background. Also hand it the earlier findings and which commit addressed each, but not why you dismissed any, so it checks each fix holds and the new commits add no bug. Reviewers only report, you fix. At most two such rounds per PR."
fi

[ -n "$context" ] || exit 0
jq -cn --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
