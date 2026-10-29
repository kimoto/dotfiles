#!/bin/bash
# Claude Code hook that makes review a step the agent cannot skip by
# forgetting (registered by bin/install_claude_review_gate.sh, and by
# settings-cloud.json in a container):
#
#   PreToolUse (gh pr create, or a GitHub MCP create_pull_request): the first
#     create on a branch is denied until its review is marked done, so the
#     PR's code and text are reviewed before they become public.
#   Stop: when the session pauses with commits after the last mark, send it
#     back to re-check only those, at most two rounds per branch.
#   mark <repo-dir> <session-id>: record that the branch's HEAD is reviewed.
#
# The marks live per branch under $XDG_STATE_HOME/claude-review; the agent can
# still mark without reviewing, but it can no longer skip review by not
# remembering it.
set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-review"
# When a re-check was last asked for, and for which HEAD. A sibling of
# state_dir, so no branch name can collide with it.
asked_dir="$state_dir-asked"
max_rounds=2
# A re-review takes under a minute; a stop past this with no mark means the
# ask was ignored, so it is made once more, and then left to the mark.
reask_after=600
max_asks=2

branch_key() { printf '%s' "$1" | tr '/' '%'; }
mark_file() { printf '%s/%s' "$state_dir" "$(branch_key "$1")"; }
asked_file() { printf '%s/%s' "$asked_dir" "$(branch_key "$1")"; }

# The path this hook ran from, quoted for the agent to paste: a container has
# the repo's bin/, not ~/bin. Only built where an instruction needs it, since
# every Bash call runs this script.
gate_cmd() { printf "'%s/%s'" "$(cd "$(dirname "$0")" && pwd -P)" "$(basename "$0")"; }

if [ "${1:-}" = mark ]; then
  dir=${2:?usage: claude_review_gate.sh mark <repo-dir> <session-id>}
  session=${3:-}
  branch=$(git -C "$dir" symbolic-ref --short -q HEAD) || { echo "not on a branch: $dir" >&2; exit 1; }
  sha=$(git -C "$dir" rev-parse HEAD) || exit 1
  dir=$(git -C "$dir" rev-parse --show-toplevel) || exit 1
  mkdir -p "$state_dir"
  f=$(mark_file "$branch")
  rounds=-1
  [ -f "$f" ] && read -r _ rounds _ _ <"$f"
  printf '%s %s %s %s\n' "$sha" "$((rounds + 1))" "$session" "$dir" >"$f"
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)

# Every Bash call passes through here; leave fast unless it can be a PR create.
case "$payload" in
  *create_pull_request* | *'"hook_event_name":"Stop"'* | *'"hook_event_name": "Stop"'*) ;;
  *pr*create*) ;;
  *) exit 0 ;;
esac

{
  IFS= read -r event
  IFS= read -r session
  IFS= read -r cwd
  IFS= read -r tool
  IFS= read -r active
  IFS= read -r head
  IFS= read -r cmd
} < <(jq -r '(.hook_event_name // ""), (.session_id // ""), (.cwd // ""), (.tool_name // ""),
  (.stop_hook_active // false), (.tool_input.head // ""),
  (.tool_input.command // "" | gsub("\n"; "; "))' <<<"$payload" 2>/dev/null)

# Codex takes correctness where enabled: a different model misses different
# things. Its switch already says this machine's code may go to OpenAI.
correctness_reviewer() {
  local companion=""
  if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] \
    && jq -e '.enabledPlugins["codex@openai-codex"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    companion=$(printf '%s\n' "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs \
      | sort -V | tail -1)
  fi
  if [ -f "$companion" ]; then
    # shellcheck disable=SC2016 # backticks are Markdown for the agent
    printf '`node "%s" review --base <the base branch>`' "$companion"
  else
    printf 'the review-correctness subagent'
  fi
}

if [ "$event" = Stop ]; then
  [ "$active" = true ] && exit 0
  [ -d "$state_dir" ] || exit 0
  todo=""
  for f in "$state_dir"/*; do
    [ -f "$f" ] || continue
    branch=$(basename "$f" | tr '%' '/')
    read -r sha rounds owner dir <"$f"
    now=$(git -C "$dir" rev-parse -q --verify "refs/heads/$branch") || { rm -f "$f" "$(asked_file "$branch")"; continue; }
    [ "$owner" = "$session" ] && [ "$now" != "$sha" ] && [ "$rounds" -lt "$max_rounds" ] || continue
    asked_path=$(asked_file "$branch")
    asked_sha="" asked_at=0 asks=0
    [ -f "$asked_path" ] && read -r asked_sha asked_at asks <"$asked_path"
    if [ "$asked_sha" = "$now" ]; then
      [ $(($(date +%s) - asked_at)) -gt "$reask_after" ] && [ "${asks:-0}" -lt "$max_asks" ] || continue
    else
      asks=0
    fi
    mkdir -p "$asked_dir"
    printf '%s %s %s\n' "$now" "$(date +%s)" "$((${asks:-0} + 1))" >"$asked_path"
    todo="$todo In $dir, review $sha..$branch with $(correctness_reviewer), run_in_background; hand it the earlier findings and which commit addressed each, but not why you dismissed any, so it checks each fix holds and the new commits add no bug. Then run \`$(gate_cmd) mark '$dir' $session\`."
  done
  [ -n "$todo" ] || exit 0
  jq -cn --arg r "Before stopping, re-check the commits made since the last review. Reviewers only report; you fix.$todo" \
    '{decision: "block", reason: $r}'
  exit 0
fi

[ "$event" = PreToolUse ] || exit 0

# Which branch the PR is for: the MCP tool says it; gh takes --head/-H, or
# else the branch the session's checkout is on.
if [[ "$tool" != *__create_pull_request ]]; then
  bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
  printf '%s' "$bare" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0
  head=$(printf '%s' "$cmd" | grep -oE '(--head|-H)[= ]+[^[:space:]]+' | head -1 | sed -E 's/^(--head|-H)[= ]+//')
  [ -n "$head" ] || head=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
fi
[ -n "$head" ] || exit 0
[ -f "$(mark_file "$head")" ] && exit 0

dir=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '<the repo dir>')
reason="Review this branch ($head) before opening its PR, after fetching the base. Reviewers only report; you fix, commit and push. Give each only the repo path, the branch's commits not on the base, and the PR's purpose, not your reasoning. Start, all with run_in_background: $(correctness_reviewer); the review-rules subagent, also given the PR title and body you are about to use;"
for sweep in refactor-sweep test-sweep security-audit bottleneck-sweep; do
  reason="$reason a subagent that reads ~/.claude/skills/$sweep/SKILL.md and follows its diff mode (差分モード);"
done
reason="${reason%;}. Keep security findings out of the PR text on a public repo. When done, run \`$(gate_cmd) mark '$dir' $session\` and create the PR again."
jq -cn --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $r}}'
