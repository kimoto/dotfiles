#!/bin/sh
# Git pre-commit hook for every repo on the machine, registered as a
# config-based hook in .gitconfig ([hook "dotfiles-gitleaks"], Git 2.54+): scan
# what is staged with gitleaks and refuse the commit while a secret is found.
#
# Why a config-based hook and not core.hooksPath: a global core.hooksPath
# replaces each repo's .git/hooks, so lefthook, pre-commit and friends stop
# running. A config-based hook runs alongside them (the repo's own hook runs
# after it). Older Git ignores the [hook "..."] section.
#
# ★The repo wins. When the repo's installed pre-commit already runs gitleaks
#  (--repo-owns says so), this stays out. Otherwise gitleaks reads the repo's
#  own .gitleaks.toml and .gitleaksignore, since it scans from the repo root.
#  A repo opts out with `git config hook.dotfiles-gitleaks.enabled false`.
# ⚠️ Fails open without gitleaks: a hook that blocks every commit on a machine
#    mid-bootstrap is one that gets removed.
#
# --repo-owns <dir>: exit 0 when that repo's installed pre-commit runs
# gitleaks itself, 1 otherwise. bin/claude_commit_secret_scan.sh asks the same
# question, so the two cannot disagree about who owns the scan.
set -u

repo_owns() {
  root=$1
  hooks_dir=$(git -C "$root" rev-parse --path-format=absolute --git-path hooks 2>/dev/null) || return 1
  # Installed, and a config it reads names gitleaks. A config alone is not
  # enough: a hook manager that was never installed runs nothing.
  [ -x "$hooks_dir/pre-commit" ] || return 1
  for f in "$hooks_dir/pre-commit" "$root/lefthook.yml" "$root/.lefthook.yml" \
    "$root/lefthook-local.yml" "$root/.lefthook-local.yml" \
    "$root/.pre-commit-config.yaml" "$root/.husky/pre-commit"; do
    [ -r "$f" ] && grep -q gitleaks "$f" 2>/dev/null && return 0
  done
  return 1
}

if [ "${1:-}" = "--repo-owns" ]; then
  repo_owns "${2:-.}"
  exit $?
fi

command -v gitleaks >/dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
repo_owns "$root" && exit 0

cd "$root" || exit 0
gitleaks git --staged --no-banner --redact --log-level error --exit-code 1 -v . >&2
status=$?
[ "$status" -eq 1 ] || exit 0
echo "gitleaks: commit refused, a secret is staged (values redacted above)." >&2
echo "Remove it (and rotate it if real). False positive: add its Fingerprint to .gitleaksignore." >&2
exit 1
