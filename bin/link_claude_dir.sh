#!/bin/bash
# The ~/.claude entries, for a container where bin/mklink.sh never runs: a cloud
# session (Setup script field at claude.ai/code) or this repo's web sandbox.
#
#     /root/dotfiles/bin/link_claude_dir.sh --cloud || true
#
# `|| true` matters: a non-zero exit there fails the session, and a failed link
# exits non-zero here. Never the rest of mklink — in a container .zshrc costs a
# shell load per Bash call and its aliases point at absent tools (#252), and
# .gitconfig breaks `git commit` and takes `git config --global` into this repo.
# --cloud is opt-in because claudecode/rules-cloud is false where mklink ran.

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

# Walked, not named like mklink.sh: no rmworld list to keep in sync. Other
# tools install skills here, so an existing real directory is left alone.
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$skill")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "[claude-dir] $dest is not ours; left alone" >&2
    continue
  fi
  ln -nsf "${skill%/}" "$dest"
done

# A failed link looks like one that worked, so report what is readable.
missing=0

# Any .md: retiring a rule must not read as a broken link.
report_rules() {
  if [ -n "$(find "$2/" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then
    echo "  ok   $1"
  else
    echo "  MISS $1"
    missing=1
  fi
}

# SKILL.md is the contract; without one the skill has not arrived.
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
