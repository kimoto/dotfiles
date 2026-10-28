#!/bin/bash
# Claude Code PostToolUse hook for Bash calls (registered in every repo by
# bin/install_claude_pr_hooks.sh, and by settings-cloud.json in a container):
# after a push, remind the agent that the PR description may no longer hold;
# after `gh pr create`, have it watch the new PR so a merge, a close or a
# failing check reaches the session the way a cloud session's PR subscription
# would.
#
# Claude Code sends the tool call as JSON on stdin and reads hookSpecificOutput
# JSON back on stdout; printing nothing means "no comment". Quoted text is
# stripped before matching, so a command that only mentions a push — a grep
# pattern, an echo — leaves the hook silent.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Drop quoted strings, so only commands that actually ran are matched, at the
# start of a command in the line.
bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
starts='(^|[;&|(]|&&|\|\|)[[:space:]]*'

context=""

git_sub="${starts}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+"

# A first look right after each commit, so a plain mistake surfaces while the
# author is still in that code rather than at push. Haiku and one commit's diff
# keep it fast and cheap; the thorough review waits for the push below.
if printf '%s' "$bare" | grep -qE "${git_sub}commit([[:space:]]|\$)" \
  && ! printf '%s' "$bare" | grep -qE "commit[^;&|]*[[:space:]](--dry-run)([[:space:]]|\$)"; then
  context="A git commit just ran. Unless it only applies an earlier review's findings, start the Agent tool with model haiku and run_in_background as a subagent that has not seen this work, giving it only the repo path and the range HEAD~1..HEAD, not your reasoning. Ask for at most three plain mistakes in that commit, each with the input that breaks it, and nothing else. Keep working meanwhile; when it returns, fix what holds up."
fi

# git with any options (e.g. -C <dir>), then the push subcommand. What a
# description may hold lives in one place, the pull-requests rule every session
# already loads; the reminder only points there, so the two never drift.
if printf '%s' "$bare" | grep -qE "${git_sub}push([[:space:]]|\$)"; then
  context="${context:+$context }A git push just ran. If the pushed branch has an open pull request, re-check its title and body against ~/.claude/rules/dotfiles/pull-requests.md and fix what this push made untrue."
  # Second readers for every push that publishes code, one per viewpoint, so
  # neither crowds out the other. For correctness, Codex where its plugin is
  # enabled — that switch already says this machine's code may go to OpenAI,
  # and a different model misses different things. Otherwise, and always for
  # performance, a subagent that has not seen the work: it gets the diff, not
  # the author's reasoning, so it cannot inherit the author's blind spots. Advisory, so a
  # review that never runs costs nothing; the round cap keeps review, fix,
  # push from looping, though only as well as the agent keeps count.
  if ! printf '%s' "$bare" | grep -qE "push[^;&|]*[[:space:]](--delete|-d|--dry-run|-n|--tags)([[:space:]]|\$)"; then
    companion=""
    if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] \
      && jq -e '.enabledPlugins["codex@openai-codex"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
      companion=$(printf '%s\n' "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs \
        | sort -V | tail -1)
    fi
    context="$context If it does, also have the pushed commits reviewed, after fetching the branch the PR targets, at most two review rounds per PR; past that, list what is left in the PR body instead. Give each reviewer only the repo path, the pushed branch's commits that are not on the PR's base, and the PR's stated purpose, not your reasoning or what you think is wrong."
    if [ -f "$companion" ]; then
      context="$context For correctness, start \`node \"$companion\" review --base <the branch the PR targets>\` with run_in_background from the pushed repo."
    else
      context="$context For correctness, start a subagent that has not seen this work with the Agent tool and run_in_background, asking for correctness bugs, each with a concrete input that breaks it."
    fi
    context="$context At the same time, start another such subagent asking only about performance: work that grows with input size, repeated I/O or process spawns, slower startup, each with the case that makes it slow. When the reviews return, fix the findings that hold up and say which ones you dismissed."
  fi
fi

# The URL gh prints is the proof a PR exists; without one the create failed.
# A cloud session already hears its PRs, and its container may have no gh.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && printf '%s' "$bare" | grep -qE "${starts}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|\$)"; then
  url=$(jq -r '.tool_response | tostring' <<<"$payload" 2>/dev/null \
    | grep -oE 'https://github\.com/[^/[:space:]"]+/[^/[:space:]"]+/pull/[0-9]+' | head -1)
  if [ -n "$url" ]; then
    context="${context:+$context }A pull request was just created: $url. Unless this session can subscribe to PR activity, start \`~/bin/watch_pr.sh $url\` with run_in_background now, so its merge, close or failing check reaches you; re-arm it after you push a fix for a failed check."
  fi
fi

[ -n "$context" ] || exit 0
jq -cn --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
