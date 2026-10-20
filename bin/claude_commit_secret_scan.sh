#!/bin/bash
# Claude Code PreToolUse hook for Bash (registered by
# bin/install_claude_security_hooks.sh, and by claudecode/settings-cloud.json in
# a cloud session): before a `git commit` the model runs, scan what that commit
# can contain with gitleaks, and block it while a secret is found.
#
# Why a Claude hook and not git's own: a global core.hooksPath replaces every
# repo's .git/hooks, so lefthook, pre-commit and friends would stop running.
# This covers only the commits a Claude session makes, and leaves the repo's
# hooks exactly as they are.
#
# ★The repo wins. When its installed pre-commit already runs gitleaks, this
#  stays out (unless the commit skips hooks with --no-verify / -n). Otherwise
#  the repo's .gitleaks.toml and .gitleaksignore, when present, decide what
#  counts as a leak.
# ★What is scanned is the diff against HEAD plus untracked files, not only the
#  index: the model usually runs `git add x && git commit` as one command, and
#  at this point x is not staged yet. Scanning a little more than the commit
#  holds can block on a change it does not include; that is the safe side.
# ⚠️ Fails open when it cannot tell (no gitleaks, not a repo, unparsable input):
#    a guard that blocks every commit on a machine without gitleaks is one that
#    gets removed.
set -uo pipefail

# Untracked files larger than this are skipped: a secret is rarely in one, and
# reading a build artefact would make every commit slow.
MAX_UNTRACKED_BYTES=1048576

command -v jq >/dev/null 2>&1 || exit 0
command -v gitleaks >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
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

if [ "$skips_hooks" -eq 0 ]; then
  hooks_dir=$(git -C "$root" rev-parse --git-path hooks 2>/dev/null)
  case "$hooks_dir" in /*) ;; *) hooks_dir="$root/$hooks_dir" ;; esac
  hp=$(git -C "$root" config core.hooksPath 2>/dev/null) && {
    case "$hp" in /*) hooks_dir="$hp" ;; *) hooks_dir="$root/$hp" ;; esac
  }
  # An installed pre-commit, and a config it reads that names gitleaks: the
  # repo already scans. A config alone is not enough — a hook manager that was
  # never installed runs nothing.
  if [ -x "$hooks_dir/pre-commit" ]; then
    for f in "$hooks_dir/pre-commit" "$root"/lefthook.yml "$root"/.lefthook.yml \
      "$root"/lefthook-local.yml "$root"/.lefthook-local.yml \
      "$root"/.pre-commit-config.yaml "$root"/.husky/pre-commit; do
      [ -r "$f" ] && grep -q gitleaks "$f" 2>/dev/null && exit 0
    done
  fi
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
    git -C "$root" ls-files -z --others --exclude-standard 2>/dev/null |
      while IFS= read -r -d '' f; do
        p="$root/$f"
        [ -f "$p" ] || continue
        [ "$(wc -c <"$p")" -le "$MAX_UNTRACKED_BYTES" ] || continue
        printf '+++ %s\n' "$f"
        cat "$p"
      done
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
