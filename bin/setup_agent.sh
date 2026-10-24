#!/bin/bash
# Any container an agent, not a person, works in: the Setup script field of a
# Claude Code or Codex cloud environment, whichever repos it opens. It installs
# the check binaries and links each agent's user configuration; a repo's own git
# hooks stay that repo's job. Call it as `... || true`: a non-zero exit fails
# the session.
#
# --no-toolchain: the caller already ran install_check_tools.sh.

set -uo pipefail

# Never $PWD: a session opened on another repo never cd's in here.
BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

failed=0

if [ "${1:-}" != "--no-toolchain" ]; then
  "$BASE_DIR/bin/install_check_tools.sh" || failed=1
fi

# Codex cloud starts the agent after this setup script, so these global defaults
# and the Claude-guidance bridge are present when it discovers instructions.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$CODEX_DIR"

link_codex_file() {
  local label="$1" source="$2" destination="$3"

  if { [ -e "$destination" ] || [ -L "$destination" ]; } &&
     [ "$(readlink -f "$destination" 2>/dev/null)" != "$source" ]; then
    echo "[cloud-setup] MISS $label: $destination is not ours; left alone" >&2
    return 1
  fi
  ln -nsf "$source" "$destination"
  if [ -f "$destination" ] && [ "$(readlink -f "$destination")" = "$source" ]; then
    echo "[cloud-setup] ok   $label"
  else
    echo "[cloud-setup] MISS $label" >&2
    return 1
  fi
}

link_codex_file "Codex config" "$BASE_DIR/codex/config.toml" "$CODEX_DIR/config.toml" || failed=1
link_codex_file "Codex instructions" "$BASE_DIR/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" || failed=1

"$BASE_DIR/bin/link_claude_dir.sh" --cloud || failed=1

# The commit author, set here rather than by each agent passing `-c user.*`:
# an instruction can be forgotten, this cannot. Included, not linked: the
# container's ~/.gitconfig holds the platform's signing and proxy settings.
link_git_identity() {
  local source="$BASE_DIR/.gitconfig.agent" global="$HOME/.gitconfig"

  if [ -L "$global" ]; then
    echo "[cloud-setup] MISS git identity: $global is a symlink; left alone" >&2
    return 1
  fi
  if ! git config --global --get-all include.path 2>/dev/null | grep -qxF "$source"; then
    git config --global --add include.path "$source" || true
  fi
  if [ "$(git config --global --includes user.email)" = "$(git config --file "$source" user.email)" ]; then
    echo "[cloud-setup] ok   git identity"
  else
    echo "[cloud-setup] MISS git identity" >&2
    return 1
  fi
}

link_git_identity || failed=1

exit "$failed"
