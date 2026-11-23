#!/bin/bash
# Stops words about the owner's private life (who they work for, where they
# live, their health, their family, their hours) from reaching a public repo:
# in a commit, a commit message, a PR title or body, an issue or a comment.
#
# ★The list of words is never in this repo: a public list of what must not be
#  said says it. It comes from $PRIVATE_TERMS (one extended regex per line,
#  matched case-insensitively; CI fills it from the repo secret of the same
#  name), else from $PRIVATE_TERMS_FILE, else ~/.private_terms. Lines starting
#  with # are comments. No list: every mode passes silently — a machine that
#  was never given one has nothing to compare against.
# ⚠️ PRIVATE_TERMS_REDACT=1 (CI) reports only where a word is, never the word:
#    a public repo's Actions logs are public too.
#
#   range <rev-list args>   commits' added lines and messages (CI, pre-push)
#   text <label>            stdin, reported as <label>
#   pre-push <remote> <url> git pre-push hook ([hook "dotfiles-private-terms"]
#                           in .gitconfig): public remotes only
#   claude-hook             Claude Code PreToolUse: a commit, push or GitHub
#                           write aimed at a public repo
#
# Exit 1 on a match (2 in claude-hook, which is how Claude Code blocks a call).
set -uo pipefail

# Findings go to a file, not a variable: most scans run in a pipeline's
# subshell, where a variable set would be lost.
terms_file="" findings=""
load_terms() {
  local src="${PRIVATE_TERMS_FILE:-$HOME/.private_terms}"
  terms_file=$(mktemp) && findings=$(mktemp) || return 1
  trap 'rm -f "$terms_file" "$findings"' EXIT
  if [ -n "${PRIVATE_TERMS:-}" ]; then
    printf '%s\n' "$PRIVATE_TERMS"
  elif [ -r "$src" ]; then
    cat "$src"
  fi | tr -d '\r' | grep -vE '^[[:space:]]*(#|$)' >"$terms_file"
  [ -s "$terms_file" ]
}

# report <where> <line>: say which word matched <line>, unless redacting.
report() {
  local where=$1 line=$2 term
  if [ "${PRIVATE_TERMS_REDACT:-}" = 1 ]; then
    printf '%s: private term found\n' "$where" >>"$findings"
    return
  fi
  while IFS= read -r term; do
    if grep -qiE -e "$term" <<<"$line"; then
      printf '%s: matches "%s"\n' "$where" "$term" >>"$findings"
      return
    fi
  done <"$terms_file"
}

# flush: print the findings; true when there were none.
flush() {
  [ -s "$findings" ] || return 0
  cat "$findings" >&2
  return 1
}

# scan <label>: stdin, line by line.
scan() {
  local label=$1 n line
  while IFS=: read -r n line; do
    report "$label line $n" "$line"
  done < <(grep -niE -f "$terms_file" 2>/dev/null)
}

# scan_commits <rev-list args...>: messages and added lines of those commits.
scan_commits() {
  local sha file="" n=0 line
  for sha in $(git rev-list "$@" 2>/dev/null); do
    git log -1 --format=%B "$sha" | scan "commit ${sha:0:7} message"
    while IFS= read -r line; do
      case "$line" in
        '+++ b/'*) file=${line#+++ b/} ;;
        '+++ '*) file=${line#+++ } ;;
        '@@ '*)
          n=$(sed -E 's/^@@ -[0-9,]+ \+([0-9]+).*/\1/' <<<"$line")
          continue
          ;;
        '+'*)
          grep -qiE -f "$terms_file" <<<"${line:1}" && report "commit ${sha:0:7} $file:$n" "${line:1}"
          ;;
      esac
      case "$line" in '+'* | ' '*) n=$((n + 1)) ;; esac
    done < <(git show --no-color --no-ext-diff --unified=0 --format= "$sha")
  done
}

# is_public <owner> <repo>: true only when GitHub says so without credentials,
# cached for a week. Unknown (no network) counts as not public: CI still runs
# the same check before anything merges.
is_public() {
  local cache="${XDG_STATE_HOME:-$HOME/.local/state}/private-terms/$1%$2" v
  if [ -n "$(find "$cache" -mtime -7 2>/dev/null)" ]; then
    [ "$(cat "$cache")" = public ]
    return
  fi
  v=$(curl -fsS --max-time 3 "https://api.github.com/repos/$1/$2" 2>/dev/null |
    jq -r 'if .private == false then "public" else "private" end' 2>/dev/null) || return 1
  [ -n "$v" ] || return 1
  mkdir -p "$(dirname "$cache")" && printf '%s\n' "$v" >"$cache"
  [ "$v" = public ]
}

# owner_repo <url>: "owner repo" of a github.com remote URL.
owner_repo() {
  sed -nE 's#^(https://|ssh://)?([^@/]*@)?github\.com[:/]([^/]+)/([^/]+)$#\3 \4#p' <<<"${1%.git}"
}

claude_hook() {
  local payload tool cmd cwd bare dir root target="" owner repo f
  payload=$(cat) || exit 0
  tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)
  cwd=$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)

  if [ "$tool" != Bash ]; then
    # A GitHub write names its repo; reads (get_/list_/search_/*_read) say nothing.
    case "$tool" in
      mcp__*github*__get_* | mcp__*github*__list_* | mcp__*github*__search_* | mcp__*github*__*_read) exit 0 ;;
      mcp__*github*) ;;
      *) exit 0 ;;
    esac
    owner=$(jq -r '.tool_input.owner // empty' <<<"$payload")
    repo=$(jq -r '.tool_input.repo // empty' <<<"$payload")
    [ -n "$owner" ] && [ -n "$repo" ] && is_public "$owner" "$repo" || exit 0
    jq -r '.tool_input | del(.owner, .repo) | tostring' <<<"$payload" | scan "$tool input"
  else
    cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)
    bare=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")
    local starts='(^|[;&|(]|&&|\|\|)[[:space:]]*'
    local gitopts='([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*'
    local kind=""
    if grep -qE "${starts}git${gitopts}[[:space:]]+commit([[:space:]]|\$)" <<<"$bare"; then
      kind=commit
    elif grep -qE "${starts}git${gitopts}[[:space:]]+push([[:space:]]|\$)" <<<"$bare"; then
      kind=push
    elif grep -qE "${starts}gh[[:space:]]+(pr|issue|release|api)[[:space:]]" <<<"$bare"; then
      kind=gh
    fi
    [ -n "$kind" ] || exit 0

    dir=$(grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:];&|]+' <<<"$bare" | head -n 1 | awk '{print $3}')
    case "$dir" in "") dir=${cwd:-.} ;; /*) ;; *) dir="${cwd:-.}/$dir" ;; esac
    root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    target=$(grep -oE '(-R|--repo)[[:space:]=]+[^[:space:]/]+/[^[:space:];&|]+' <<<"$bare" | head -n 1 |
      sed -E 's#^(-R|--repo)[[:space:]=]+##; s#/# #')
    [ -n "$target" ] || [ -z "$root" ] || target=$(owner_repo "$(git -C "$root" remote get-url origin 2>/dev/null)")
    [ -n "$target" ] || exit 0
    [ -n "$root" ] || [ "$kind" = gh ] || exit 0
    # shellcheck disable=SC2086 # "owner repo", split on purpose
    is_public $target || exit 0

    printf '%s\n' "$cmd" | scan "command"
    case "$kind" in
      commit)
        # The diff against HEAD, not only the index: `git add x && git commit`
        # arrives as one command, before x is staged.
        git -C "$root" diff --no-color --no-ext-diff HEAD 2>/dev/null | grep '^+' | scan "change to commit"
        (cd "$root" && git ls-files -z --others --exclude-standard | xargs -0 -r cat 2>/dev/null) |
          scan "untracked file"
        ;;
      push)
        (cd "$root" && scan_commits HEAD --not --remotes)
        ;;
      gh)
        # The body a PR or issue reads from a file; `gh api -F key=value` is
        # no file and is skipped.
        while IFS= read -r f; do
          case "$f" in /*) ;; *) f="${cwd:-.}/$f" ;; esac
          # shellcheck disable=SC2094 # the name is only a label; scan writes elsewhere
          [ -f "$f" ] && scan "$(basename "$f")" <"$f"
        done < <(grep -oE '(--body-file|-F)[[:space:]=]+[^[:space:];&|]+' <<<"$cmd" |
          sed -E 's/^(--body-file|-F)[[:space:]=]+//')
        ;;
    esac
  fi

  if ! flush; then
    echo "This goes to a public repo and holds words about the owner's private life (listed above)." >&2
    echo "Reword it without them. If one is a false match, ask the owner; do not bypass this check." >&2
    exit 2
  fi
  exit 0
}

mode=${1:-}
[ $# -gt 0 ] && shift
load_terms || exit 0

case "$mode" in
  range) scan_commits "$@" ;;
  text) scan "${1:-stdin}" ;;
  pre-push)
    # shellcheck disable=SC2046 # "owner repo", split on purpose
    is_public $(owner_repo "${2:-}") || exit 0
    while read -r _ local_sha _ _; do
      case "$local_sha" in *[!0]*) scan_commits "$local_sha" --not --remotes ;; esac
    done
    ;;
  claude-hook) claude_hook ;;
  *)
    echo "usage: $0 range <rev-list args> | text <label> | pre-push <remote> <url> | claude-hook" >&2
    exit 64
    ;;
esac
flush
