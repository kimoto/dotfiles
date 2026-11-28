#!/bin/sh
# prefix + V (.tmux.conf): hunk on everything this branch changes, commits and
# uncommitted edits alike, live. Measured from where the branch left the
# default branch: against that branch's tip instead, every commit landed there
# since would show up reversed, as if this branch had undone it.
# Falls back to HEAD (the plain prefix + v view) with no remote to compare to.
set -eu

base="$(git merge-base origin/HEAD HEAD 2>/dev/null ||
  git merge-base origin/main HEAD 2>/dev/null ||
  echo HEAD)"
exec hunk diff --watch "$base"
