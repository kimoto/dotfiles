#!/bin/bash
# A Claude Code or Codex cloud container, from its Setup script field and from
# the Claude web-sandbox hook. Call it as `... || true`: a non-zero exit fails
# the session.

set -uo pipefail

# Never $PWD: a session opened on another repo never cd's in here.
BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

failed=0

if "$BASE_DIR/bin/install_check_tools.sh"; then
  toolchain=1
else
  toolchain=0
  failed=1
fi

# ⚠ Hooks without the toolchain refuse every commit: bin/lint_*.sh exits
# non-zero when its tool is absent.
if [ "$toolchain" -eq 1 ] && command -v lefthook >/dev/null 2>&1; then
  (cd "$BASE_DIR" && lefthook install >/dev/null) || failed=1
else
  echo "[cloud-setup] MISS git hooks: nothing checks a commit here" >&2
  failed=1
fi

# Behind the repo's interactive zsh helpers (g, b, livegrep, ...).
if ! command -v fzf >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get install -y -qq fzf >/dev/null || true
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
