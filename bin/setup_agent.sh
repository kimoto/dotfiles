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

exit "$failed"
