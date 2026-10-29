#!/bin/bash
# Claude Code hook that makes review a step the agent cannot skip by
# forgetting (registered by bin/install_claude_review_gate.sh, and by
# settings-cloud.json in a container):
#
#   PreToolUse (git push): a push carrying commits no review has seen is
#     denied once, so code is reviewed before it leaves the machine — on a
#     feature branch and on a direct push to main alike. After a mark, only the
#     commits since it are re-checked, at most two rounds per branch.
#   PreToolUse (gh pr create, or a GitHub MCP create_pull_request): the first
#     create on a branch is denied once so the PR's title and body, which no
#     push carries, are checked against the rules.
#   mark <repo-dir> <session-id>: record that the branch's HEAD is reviewed.
#
# Each stop happens once per HEAD (for a PR, once per repo and branch tip): pushing or
# creating again goes through, so a change that needs no review costs one
# retry. The agent can still mark without reviewing; what the gate rules out is
# skipping review by not remembering it.
set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-review"
# Siblings of state_dir, so no branch name can collide with them: the HEAD a
# push was last stopped for, and the branches whose PR text was asked for.
pushed_dir="$state_dir-pushed"
pr_dir="$state_dir-pr"
max_rounds=2

branch_key() { printf '%s' "$1" | tr '/' '%'; }
# One file per repo and branch: two repos each have a main. cksum is POSIX, so
# a bare container has it where shasum may be missing.
repo_key() { printf '%s@%s' "$(branch_key "$2")" "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
mark_file() { printf '%s/%s' "$state_dir" "$(repo_key "$1" "$2")"; }

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
  # Marks of branches that are gone, and stops nobody will hit again, would
  # otherwise pile up forever.
  for f in "$state_dir"/*; do
    [ -f "$f" ] || continue
    read -r _ _ _ fdir <"$f"
    name=$(basename "$f")
    git -C "$fdir" rev-parse -q --verify "refs/heads/$(printf '%s' "${name%@*}" | tr '%' '/')" >/dev/null 2>&1 \
      || rm -f "$f"
  done
  find "$pushed_dir" "$pr_dir" -type f -mtime +30 -delete 2>/dev/null
  f=$(mark_file "$dir" "$branch")
  rounds=-1
  [ -f "$f" ] && read -r _ rounds _ _ <"$f"
  printf '%s %s %s %s\n' "$sha" "$((rounds + 1))" "$session" "$dir" >"$f"
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)

# Every Bash call passes through here; leave fast unless it can be a push or a
# PR create.
case "$payload" in
  *create_pull_request* | *push* | *pr*create*) ;;
  *) exit 0 ;;
esac

{
  IFS= read -r event
  IFS= read -r session
  IFS= read -r cwd
  IFS= read -r tool
  IFS= read -r head
  IFS= read -r gh_repo
  IFS= read -r cmd
} < <(jq -r '(.hook_event_name // ""), (.session_id // ""), (.cwd // ""), (.tool_name // ""),
  (.tool_input.head // ""), ((.tool_input.owner // "") + "/" + (.tool_input.repo // "")),
  (.tool_input.command // "" | gsub("\n"; "; "))' <<<"$payload" 2>/dev/null)

[ "$event" = PreToolUse ] || exit 0

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Who reviews and what they are handed live in the review-branch skill, which a
# person can also call by hand; the hook only names the range. A machine that
# pulled but has not re-linked reads the repo's copy.
skill_ref() {
  local f="$HOME/.claude/skills/review-branch/SKILL.md"
  [ -f "$f" ] || f="$(cd -P "$(dirname "$0")" && cd .. && pwd)/claudecode/skills/review-branch/SKILL.md"
  printf 'the review-branch skill (%s)' "$f"
}

bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
starts='(^|[;&|(]|&&|\|\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
unquote() { sed -E "s/^['\"]//; s/['\"]\$//"; }

# A path as the shell would read it, as far as a hook can: ~ and $HOME expand,
# any other variable leaves it unknown (empty).
resolve() {
  local p=$1
  # shellcheck disable=SC2016 # matching the literal text $HOME
  case $p in
    '~' | '$HOME' | '${HOME}') p=$HOME ;;
    \~/*) p="$HOME/${p#\~/}" ;;
    '$HOME/'*) p="$HOME/${p#\$HOME/}" ;;
    '${HOME}/'*) p="$HOME/${p#\$\{HOME\}/}" ;;
  esac
  case $p in *'$'*) return ;; esac
  printf '%s' "$p"
}

# Deny the push when this branch carries commits no review has seen. Returns
# when it may go.
judge_branch() {
  local dir=$1 branch=$2 now pushed sha="" rounds=0 count
  now=$(git -C "$dir" rev-parse -q --verify "refs/heads/$branch") || return 0
  pushed="$pushed_dir/$(repo_key "$dir" "$branch")"
  [ "$(cat "$pushed" 2>/dev/null)" = "$now" ] && return 0

  [ -f "$(mark_file "$dir" "$branch")" ] && read -r sha rounds _ _ <"$(mark_file "$dir" "$branch")"
  [ "$sha" = "$now" ] && return 0
  if [ -n "$sha" ] && git -C "$dir" merge-base --is-ancestor "$sha" "$now" 2>/dev/null; then
    # Commits a pull brought in are already on a remote; only new ones count.
    count=$(git -C "$dir" rev-list --count "$sha..$now" --not --remotes 2>/dev/null) || return 0
    [ "$count" -gt 0 ] && [ "$rounds" -lt "$max_rounds" ] || return 0
    mkdir -p "$pushed_dir" && printf '%s\n' "$now" >"$pushed"
    deny "Before this push, re-check the commits made since the last review (\`git -C '$dir' log $sha..$branch --not --remotes\`) as $(skill_ref) says under 再確認. Then run \`$(gate_cmd) mark '$dir' $session\` and push again."
  fi

  count=$(git -C "$dir" rev-list --count "$now" --not --remotes 2>/dev/null) || return 0
  [ "$count" -gt 0 ] || return 0
  mkdir -p "$pushed_dir" && printf '%s\n' "$now" >"$pushed"
  deny "This push publishes $count commit(s) on $branch that no review has seen (\`git -C '$dir' log $branch --not --remotes\`). Review them before they leave this machine, as $(skill_ref) says. Then run \`$(gate_cmd) mark '$dir' $session\` and push again. If these commits need no review (docs only, a revert), say why and push again."
}

# git with any options (e.g. -C <dir>), then the push subcommand. A wrapper
# such as sudo or bash -c is not followed: the gate stops forgetting, not
# evasion.
push_gate() {
  local dir=$cwd pre cd_dir c_dir w skip=0 tags=0 src b i
  local re='^(.*)git([[:space:]][^;&|]*)?[[:space:]]push([[:space:]]|$)'
  local -a words=() branches=()
  # What the shell runs before the (last) push: its last cd, outside a
  # subshell, sets the directory, and git -C is taken relative to that.
  [[ $cmd =~ $re ]] || return 0
  pre=${BASH_REMATCH[1]}
  cd_dir=$(printf '%s' "$pre" | grep -oE "(^|[;&|])[[:space:]]*cd[[:space:]]+('[^']*'|\"[^\"]*\"|[^[:space:];&|]+)" | tail -1 \
    | sed -E 's/^[;&|]?[[:space:]]*cd[[:space:]]+//' | unquote)
  if [ -n "$cd_dir" ]; then
    cd_dir=$(resolve "$cd_dir")
    case $cd_dir in '') ;; /*) dir=$cd_dir ;; *) dir="$dir/$cd_dir" ;; esac
  fi
  c_dir=$(printf '%s' "${BASH_REMATCH[0]#"$pre"}" | grep -oE "git[[:space:]]+-C[[:space:]]+('[^']*'|\"[^\"]*\"|[^[:space:]]+)" \
    | head -1 | sed -E 's/^git[[:space:]]+-C[[:space:]]+//' | unquote)
  if [ -n "$c_dir" ]; then
    c_dir=$(resolve "$c_dir")
    case $c_dir in '') ;; /*) dir=$c_dir ;; *) dir="$dir/$c_dir" ;; esac
  fi
  dir=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0

  # What is pushed: every refspec whose source is a local branch, else the
  # branch checked out. A delete or a tags-only push carries no commits.
  set -f
  # shellcheck disable=SC2046 # split the push's own words
  set -- $(printf '%s' "$bare" | sed -E 's/.*[[:space:]]push([[:space:]]|$)//; s/[;&|)].*//')
  set +f
  for w in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case $w in
      --delete | -d | :*) return 0 ;;
      --tags) tags=1 ;;
      -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
      -*) ;;
      *) words+=("$w") ;;
    esac
  done
  # Indexed, not "${words[@]:1}": bash 3.2 calls an empty array unbound.
  for ((i = 1; i < ${#words[@]}; i++)); do
    src=${words[i]#+} src=${src%%:*} src=${src#refs/heads/}
    if [ -z "$src" ] || [ "$src" = HEAD ]; then
      b=$(git -C "$dir" symbolic-ref --short -q HEAD) && branches+=("$b")
    elif git -C "$dir" rev-parse -q --verify "refs/heads/$src" >/dev/null; then
      branches+=("$src")
    fi
  done
  if [ "${#words[@]}" -lt 2 ]; then
    [ "$tags" -eq 0 ] || return 0
    b=$(git -C "$dir" symbolic-ref --short -q HEAD) && branches+=("$b")
  fi
  for ((i = 0; i < ${#branches[@]}; i++)); do judge_branch "$dir" "${branches[i]}"; done
}

if [ "$tool" = Bash ] && printf '%s' "$bare" \
  | grep -qE "${starts}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|\$)"; then
  push_gate
fi

# Which branch the PR is for: the MCP tool says it; gh takes --head/-H, or
# else the branch the session's checkout is on. The ask is kept per repo and
# branch tip, so a branch name used again later is asked again.
dir=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '<the repo dir>')
if [[ "$tool" == *__create_pull_request ]]; then
  where=$gh_repo tip=""
else
  printf '%s' "$bare" | grep -qE "${starts}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|\$)" || exit 0
  head=$(printf '%s' "$cmd" | grep -oE '(--head|-H)[= ]+[^[:space:]]+' | head -1 | sed -E 's/^(--head|-H)[= ]+//')
  [ -n "$head" ] || head=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
  where=$dir tip=$(git -C "$cwd" rev-parse -q --verify "refs/heads/$head" 2>/dev/null)
fi
[ -n "$head" ] || exit 0
asked="$pr_dir/$(repo_key "$where$tip" "$head")"
[ -f "$asked" ] && exit 0
mkdir -p "$pr_dir" && : >"$asked"
deny "Before opening the PR for $head in $dir, check the title and body you are about to use as $(skill_ref) says under PR の題と本文, then create the PR again."
