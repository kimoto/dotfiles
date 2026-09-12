#!/bin/bash
# Link this repo's ~/.claude entries into $HOME where bin/mklink.sh never runs:
# a Claude Code cloud session, or this repo's own web sandbox. Goes in the
# environment's Setup script field at claude.ai/code, after the clone:
#
#     /root/dotfiles/bin/link_claude_dir.sh --cloud || true
#
# The `|| true` is load-bearing: a non-zero exit there fails the whole session,
# and this script reports a failed link by exiting non-zero.
#
# Only ~/.claude, never mklink.sh. .zshrc costs a shell load on every Bash call
# rather than one per login, and with no Homebrew its aliases take `cat` and
# `curl` away instead of replacing them (#252). .gitconfig breaks `git commit`
# on a GPG key the container lacks, and the session's own `git config --global`
# then writes through the symlink into this repo.
#
# --cloud adds claudecode/rules-cloud: a flag and not the default, because every
# line of it is false on a machine where mklink ran.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CLAUDE_DIR="${HOME}/.claude"

with_cloud=0
[ "${1:-}" = "--cloud" ] && with_cloud=1

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/skills"

ln -nsf "$BASE_DIR/claudecode/rules" "$CLAUDE_DIR/rules/dotfiles"
if [ "$with_cloud" -eq 1 ]; then
  ln -nsf "$BASE_DIR/claudecode/rules-cloud" "$CLAUDE_DIR/rules/dotfiles-cloud"
fi

# Walked, not named like mklink.sh: nothing here pairs with a list in
# rmworld.sh, so that drift is avoidable. Other tools install their own skills
# here, so a destination that is already a real directory is left alone.
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$skill")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "[claude-dir] $dest is not ours; left alone" >&2
    continue
  fi
  ln -nsf "${skill%/}" "$dest"
done

# A failed link looks exactly like one that worked, and a rule that did not load
# is silent, so report what is readable rather than what was attempted.
missing=0

# Any .md, not a named one: retiring a rule must not read as a broken link.
report_rules() {
  if [ -n "$(find "$2/" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then
    echo "  ok   $1"
  else
    echo "  MISS $1"
    missing=1
  fi
}

# SKILL.md is the contract, so a skill without one has not arrived.
report_skill() {
  if [ -f "$2/SKILL.md" ]; then
    echo "  ok   skill $1"
  else
    echo "  MISS skill $1"
    missing=1
  fi
}

echo "[claude-dir]"
report_rules "rules" "$CLAUDE_DIR/rules/dotfiles"
if [ "$with_cloud" -eq 1 ]; then
  report_rules "cloud rules" "$CLAUDE_DIR/rules/dotfiles-cloud"
fi
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  report_skill "$name" "$CLAUDE_DIR/skills/$name"
done

exit "$missing"
