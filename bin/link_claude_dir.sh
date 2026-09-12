#!/bin/bash
# Link this repo's ~/.claude entries into $HOME, for a container where
# bin/mklink.sh never runs: a Claude Code cloud session, or this repo's own web
# sandbox. Paste into the environment's Setup script field at claude.ai/code
# together with the clone that puts the repo on disk:
#
#     #!/bin/bash
#     git clone --depth 1 https://github.com/kimoto/dotfiles /root/dotfiles || exit 0
#     /root/dotfiles/bin/link_claude_dir.sh --cloud || true
#
# The `|| true` is load-bearing there: a non-zero exit from the Setup script
# fails the whole session, and this script reports a failed link by exiting
# non-zero so a caller that can afford to care still can.
#
# One script rather than one per caller, because the callers cannot see each
# other: a rename would move one and leave the rest pointing nowhere, and a rule
# that did not load looks exactly like a rule with nothing to say.
#
# Not mklink.sh, because nobody types at a prompt in a container and the rest of
# what mklink links costs more there than it gives:
#   - .zshrc — the Bash tool starts a shell per call, so the config's load is
#     paid per command instead of once per login. With no Homebrew its aliases
#     also point at tools that are not installed, which takes `cat` and `curl`
#     away rather than replacing them (#252).
#   - .gitconfig — the container's own carries the session's git identity and
#     ssh signing setup. Replacing it makes `git commit` fail on a GPG key that
#     is not there, and `git config --global` then writes through the symlink
#     into this repo's tracked file.
#
# --cloud adds claudecode/rules-cloud, which says what a container lacks. It is
# a flag rather than the default so a caller on a machine where mklink ran
# cannot pull in a rule that is false there.

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

# Walked rather than named, unlike mklink.sh: nothing here pairs with a second
# list in bin/rmworld.sh, so the drift that made mklink name them is avoidable.
# The other half of mklink's reason still holds — other tools install their own
# skills into ~/.claude/skills — so a destination that is already a real
# directory is left where it is.
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$skill")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "[claude-dir] $dest is not ours; left alone" >&2
    continue
  fi
  ln -nsf "${skill%/}" "$dest"
done

# A link that failed looks exactly like one that worked, and a rule that did not
# load is silent by nature, so report what is readable now rather than what was
# attempted.
missing=0

# A rules entry is healthy when it resolves to a directory with a rule in it.
# Not a named file: rename or retire one rule and a pinned check reads MISS
# while the link is fine, a false alarm in the only output a container shows.
report_rules() {
  if [ -n "$(find "$2/" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then
    echo "  ok   $1"
  else
    echo "  MISS $1"
    missing=1
  fi
}

report_skill() {
  # SKILL.md is the skill's contract, not an incidental filename, so a skill
  # without one has not arrived whatever the link says.
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
