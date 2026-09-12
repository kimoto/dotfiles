#!/bin/bash
# Set up a Claude Code cloud session's $HOME — the ~/.claude entries, nothing else.
#
# Runs from the environment's Setup script field at claude.ai/code, which holds
# the clone because the script cannot link what is not on disk yet:
#
#     #!/bin/bash
#     git clone --depth 1 https://github.com/kimoto/dotfiles /root/dotfiles || exit 0
#     /root/dotfiles/bin/setup_cloud_session.sh || true
#
# Not mklink.sh, because nobody types at a prompt in a cloud container and the
# rest of what mklink links costs more there than it gives:
#   - .zshrc — the Bash tool starts a shell per call, so the config's load is
#     paid per command instead of once per login. With no Homebrew its aliases
#     also point at tools that are not installed, which takes `cat` and `curl`
#     away rather than replacing them (#252).
#   - .gitconfig — the container's own holds the session's git identity and its
#     ssh signing setup. Replacing it makes `git commit` fail on a GPG key that
#     is not there, and `git config --global` then writes through the symlink
#     into this repo's tracked file.
#
# Two constraints the Setup script field imposes, both load-bearing here:
# a non-zero exit fails the session (so this never exits non-zero), and work
# past five minutes is dropped from the environment snapshot (so every session
# would pay again). Linking costs a second.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CLAUDE_DIR="${HOME}/.claude"

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/skills"

ln -nsf "$BASE_DIR/claudecode/rules"       "$CLAUDE_DIR/rules/dotfiles"
ln -nsf "$BASE_DIR/claudecode/rules-cloud" "$CLAUDE_DIR/rules/dotfiles-cloud"

# Walked rather than named, unlike mklink.sh: nothing here pairs with a second
# list in bin/rmworld.sh, so the drift that made mklink name them is avoidable.
# The other half of mklink's reason still holds — other tools install their own
# skills into ~/.claude/skills — so a destination that is already a real
# directory is left where it is.
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$skill")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "[cloud-session] $dest is not ours; left alone" >&2
    continue
  fi
  ln -nsf "${skill%/}" "$dest"
done

# A link that failed looks exactly like one that worked, and a rule that did not
# load is silent by nature, so report what is actually readable now.
missing=0
report() {
  if [ -e "$2" ]; then
    echo "  ok   $1"
  else
    echo "  MISS $1"
    missing=1
  fi
}

echo "[cloud-session]"
report "rules"       "$CLAUDE_DIR/rules/dotfiles/writing.md"
report "cloud scope" "$CLAUDE_DIR/rules/dotfiles-cloud/scope.md"
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  report "skill $(basename "$skill")" "$CLAUDE_DIR/skills/$(basename "$skill")/SKILL.md"
done
[ "$missing" -eq 0 ] \
  || echo "[cloud-session] the MISS entries above will not load this session" >&2

exit 0
