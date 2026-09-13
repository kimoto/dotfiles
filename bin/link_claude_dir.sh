#!/bin/bash
# From the Setup script field at claude.ai/code and from the web-sandbox hook,
# always as `... --cloud || true` — a non-zero exit there fails the whole
# session, and a failed link exits non-zero here.
#
# Never the rest of mklink in a container: .zshrc costs a shell load per Bash
# call and its aliases point at absent tools (#252); .gitconfig breaks
# `git commit` and takes `git config --global` into this repo.
#
# --cloud is opt-in: claudecode/rules-cloud is false where mklink ran.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CLAUDE_DIR="${HOME}/.claude"

with_cloud=0
[ "${1:-}" = "--cloud" ] && with_cloud=1

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/skills"

cloud_dest="$CLAUDE_DIR/rules/dotfiles-cloud"
settings_src="$BASE_DIR/claudecode/settings-cloud.json"
settings_dest="$CLAUDE_DIR/settings.json"

ln -nsf "$BASE_DIR/claudecode/rules" "$CLAUDE_DIR/rules/dotfiles"
if [ "$with_cloud" -eq 1 ]; then
  ln -nsf "$BASE_DIR/claudecode/rules-cloud" "$cloud_dest"
elif [ -L "$cloud_dest" ]; then
  # Not linking it is not enough: a run without --cloud says this $HOME is one
  # where every line of rules-cloud is false, and an earlier --cloud run in the
  # same $HOME would otherwise go on claiming `cat` is cat and `>` overwrites.
  rm -f "$cloud_dest"
fi

# ⚠ Claude Code's own path, not a name we own: anything there but our own link
# belongs to this machine, and linking over it would take it into this checkout.
if [ "$with_cloud" -eq 1 ]; then
  if { [ -e "$settings_dest" ] || [ -L "$settings_dest" ]; } &&
     [ "$(readlink -f "$settings_dest" 2>/dev/null)" != "$settings_src" ]; then
    echo "[claude-dir] $settings_dest is not ours; left alone" >&2
  else
    ln -nsf "$settings_src" "$settings_dest"
  fi
elif [ "$(readlink -f "$settings_dest" 2>/dev/null)" = "$settings_src" ]; then
  rm -f "$settings_dest"
fi

# Other tools install skills here too, so an existing real directory is theirs.
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$skill")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "[claude-dir] $dest is not ours; left alone" >&2
    continue
  fi
  ln -nsf "${skill%/}" "$dest"
done

# A failed link looks like one that worked; silence is the failure mode.
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

report_link() {
  if [ "$(readlink -f "$2" 2>/dev/null)" = "$3" ]; then
    echo "  ok   $1"
  else
    echo "  MISS $1"
    missing=1
  fi
}

# SKILL.md is the contract, not just a file that happens to be there — and the
# directory we leave alone above is another tool's, holding its own SKILL.md.
# So follow the link to our copy: what loads under our name may not be ours.
report_skill() {
  if [ "$(readlink -f "$2" 2>/dev/null)" = "$3" ] && [ -f "$2/SKILL.md" ]; then
    echo "  ok   skill $1"
  else
    echo "  MISS skill $1"
    missing=1
  fi
}

echo "[claude-dir]"
report_rules "rules" "$CLAUDE_DIR/rules/dotfiles"
if [ "$with_cloud" -eq 1 ]; then
  report_rules "cloud rules" "$cloud_dest"
elif [ -e "$cloud_dest" ] || [ -L "$cloud_dest" ]; then
  echo "  MISS cloud rules still in place without --cloud"
  missing=1
fi
if [ "$with_cloud" -eq 1 ]; then
  report_link "cloud settings" "$settings_dest" "$settings_src"
elif [ "$(readlink -f "$settings_dest" 2>/dev/null)" = "$settings_src" ]; then
  echo "  MISS cloud settings still in place without --cloud"
  missing=1
fi
for skill in "$BASE_DIR"/claudecode/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  report_skill "$name" "$CLAUDE_DIR/skills/$name" "${skill%/}"
done

exit "$missing"
