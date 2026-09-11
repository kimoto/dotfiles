#!/bin/bash

# Cut a linked worktree for a new branch, off the *remote* default branch.
#
# Why a tool and not two lines of git: `git worktree add` branches from HEAD,
# which is whatever the primary checkout was left on — so a worktree started
# while the last PR was still checked out silently inherits that PR's commits,
# and the mistake only surfaces at review time. The base belongs inside the
# tool, not in the hand that calls it.
#
# Usage:
#   worktree_new.sh <type>/<short-desc>     # prints the worktree path
#
# stdout is the path and nothing else, so it composes:
#   cd "$(worktree_new.sh feat/thing)"      # the zsh `W` helper does exactly this
# Everything a human reads goes to stderr.
#
# Idempotent: called again for the same branch it prints the existing path and
# changes nothing, so a repeated call never discards work in progress.
#
# Env: DOTFILES_WORKTREE_ROOT overrides where worktrees live (default
# ~/.worktrees). It sits outside the ghq tree on purpose — a sibling of the
# checkout would show up in `ghq list`, and `g` would start offering worktrees
# as if they were separate clones.

set -euo pipefail

branch="${1:-}"

if [ -z "$branch" ]; then
    echo "usage: $(basename "$0") <type>/<short-desc>" >&2
    exit 2
fi

# Same type set as check_commit_msg.sh: a branch and the commits on it are
# describing one change, so they answer to one vocabulary.
if ! echo "$branch" | grep -qE '^(feat|fix|chore|docs|refactor|ci|test|revert)/[a-z0-9][a-z0-9._-]*$'; then
    echo "x Not a valid branch name: $branch" >&2
    echo "  expected <type>/<short-desc>, e.g. feat/ghostty-opacity-toggle" >&2
    echo "  type: feat|fix|chore|docs|refactor|ci|test|revert" >&2
    exit 1
fi

if ! git rev-parse --git-common-dir >/dev/null 2>&1; then
    echo "x not a git repository: $PWD" >&2
    exit 1
fi

# --git-common-dir, not --show-toplevel: run from inside a linked worktree this
# still resolves to the primary checkout, so every worktree of one repo lands
# under the same directory instead of nesting a level deeper each time.
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
repo_name=$(basename "$(dirname "$common_dir")")

root="${DOTFILES_WORKTREE_ROOT:-$HOME/.worktrees}"
target="$root/$repo_name/${branch//\//-}"

# Where is this branch checked out already, if anywhere? `git worktree add`
# refuses a branch that is checked out elsewhere, and its own error names no
# remedy — so answer that here, before doing any work.
existing=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
    /^worktree /  { path = substr($0, 10) }
    /^branch /    { if (substr($0, 8) == b) { print path; exit } }
')

if [ -n "$existing" ]; then
    if [ "$existing" = "$target" ]; then
        echo "[worktree] '$branch' already there — reusing it, nothing touched" >&2
        echo "$target"
        exit 0
    fi
    echo "x '$branch' is already checked out at: $existing" >&2
    echo "  finish or move that checkout first, or pick another branch name" >&2
    exit 1
fi

# The default branch as origin itself reports it, so a repo on 'master' (or
# anything else) needs no flag here.
default_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -z "$default_ref" ]; then
    if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
        default_ref="origin/main"
    elif git rev-parse --verify --quiet refs/remotes/origin/master >/dev/null; then
        default_ref="origin/master"
    else
        echo "x cannot tell which branch origin defaults to" >&2
        echo "  set it once: git remote set-head origin --auto" >&2
        exit 1
    fi
fi

# Offline is not fatal: branching off the last-known origin ref still beats
# branching off HEAD. But say so, or a stale base reads as a fresh one.
if ! git fetch --quiet origin "${default_ref#origin/}" 2>/dev/null; then
    echo "[worktree] could not reach origin — basing on the last-known $default_ref" >&2
fi

mkdir -p "$(dirname "$target")"

# An existing branch is reused as it stands. Re-pointing it at the default
# branch would throw away commits the caller asked to keep working on.
if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git worktree add "$target" "$branch" >&2
else
    git worktree add -b "$branch" "$target" "$default_ref" >&2
fi

echo "$target"
