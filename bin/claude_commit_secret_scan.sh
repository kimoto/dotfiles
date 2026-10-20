#!/bin/bash
# Stops a `git commit` that Claude is about to run when gitleaks finds a secret
# in it. Claude Code PreToolUse hook for Bash, registered by
# bin/install_claude_secret_scan_hook.sh (and claudecode/settings-cloud.json).
#
# Only needed where Git is older than 2.54. On 2.54+ the .gitconfig hook
# (bin/git_hook_gitleaks.sh) scans every commit, Claude's or not.
#
# 1. Not a `git commit`: let it through.
# 2. Git will scan it itself: let it through. That is Git 2.54+ with the
#    .gitconfig hook, or a repo whose installed pre-commit runs gitleaks
#    (git_hook_gitleaks.sh --repo-owns, so the two cannot disagree).
#    --no-verify / -n skips those hooks, so such a commit is scanned here.
# 3. Otherwise scan the diff against HEAD plus untracked files, and block with
#    the redacted findings. Not only the index: Claude usually runs
#    `git add x && git commit` as one command, and x is not staged yet.
#    The repo's .gitleaks.toml / .gitleaksignore decide what counts.
#
# ⚠️ Fails open when it cannot tell (no gitleaks, not a repo, unparsable input):
#    a guard that blocks every commit on a machine without gitleaks is one that
#    gets removed.
set -uo pipefail

HERE=$(dirname "$(readlink -f "$0")")

# Untracked files larger than this are skipped: a secret is rarely in one, and
# reading a build artefact would make every commit slow.
MAX_UNTRACKED_BYTES=1048576

command -v jq >/dev/null 2>&1 || exit 0
command -v gitleaks >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
# Runs before every Bash call, so leave without starting jq when the command
# cannot be a commit.
[[ "$payload" == *commit* ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Same shape as .claude/hooks/pr-description-reminder.sh: drop quoted text, then
# look for git (with options such as -C <dir>) followed by commit, at the start
# of a command in the line.
bare=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
commit_re='(^|[;&|(]|&&|\|\|)[[:space:]]*git'
commit_re+='([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'
grep -qE "$commit_re" <<<"$bare" || exit 0

# git -C <dir> commit: the commit happens there, not in cwd.
dir=$(grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:];&|]+' <<<"$bare" | head -n 1 | awk '{print $3}')
if [ -n "$dir" ]; then
  case "$dir" in /*) ;; *) dir="${cwd:-.}/$dir" ;; esac
else
  dir="${cwd:-.}"
fi
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0

skips_hooks=0
grep -qE '(^|[[:space:]])(--no-verify|-[A-Za-z]*n[A-Za-z]*)([[:space:]]|$)' \
  <<<"$(grep -oE 'commit([[:space:]]+[^;&|]*)?' <<<"$bare")" && skips_hooks=1

# git_version_ge <major> <minor>
git_version_ge() {
  local v maj min
  v=$(git --version 2>/dev/null | sed -nE 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/p')
  read -r maj min <<<"$v"
  [ -n "${maj:-}" ] && { [ "$maj" -gt "$1" ] || { [ "$maj" -eq "$1" ] && [ "$min" -ge "$2" ]; }; }
}

if [ "$skips_hooks" -eq 0 ]; then
  # Git 2.54+ with the .gitconfig hook: git itself scans at commit time, or the
  # repo opted out of it (hook.dotfiles-gitleaks.enabled=false). Either way it
  # is not this hook's call.
  if git_version_ge 2 54 &&
    git -C "$root" config --get-regexp '^hook\..*\.command$' 2>/dev/null | grep -q git_hook_gitleaks.sh; then
    exit 0
  fi
  "$HERE/git_hook_gitleaks.sh" --repo-owns "$root" && exit 0
fi

args=(stdin --no-banner --no-color --redact --log-level error --exit-code 1)
[ -r "$root/.gitleaks.toml" ] && args+=(--config "$root/.gitleaks.toml")
args+=(--gitleaks-ignore-path "$root")

if git -C "$root" rev-parse --verify -q HEAD >/dev/null; then
  base=HEAD
else
  base=$(git -C "$root" hash-object -t tree /dev/null)
fi

report=$(
  {
    git -C "$root" diff --no-ext-diff --no-color "$base" 2>/dev/null
    # One find and one awk for all files, not a process per file: a repo with
    # thousands of untracked files would otherwise take seconds.
    # shellcheck disable=SC2016 # "$@" and "$0" belong to the inner sh
    (cd "$root" && git ls-files -z --others --exclude-standard 2>/dev/null |
      xargs -0 -r sh -c 'find "$@" -maxdepth 0 -type f -size -"$0"c -print0' "$((MAX_UNTRACKED_BYTES + 1))" |
      xargs -0 -r awk 'FNR == 1 { print "+++ " FILENAME } { print }')
  } | gitleaks "${args[@]}" -v 2>&1
)
status=$?
[ "$status" -eq 1 ] || exit 0

{
  echo "gitleaks found what looks like a secret in the changes this commit can include (values redacted):"
  printf '%s\n' "$report" | grep -E '^(Finding|RuleID|File|Line|Secret):' | head -n 40
  echo "Remove it from the change (and rotate it if it is real) before committing."
  echo "If it is a false positive, ask the user; do not bypass this check yourself."
} >&2
exit 2
