#!/bin/bash
# A cloud container, from the Setup script field at claude.ai/code and from the
# web-sandbox hook. Call it as `... || true`: a non-zero exit fails the session.

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

"$BASE_DIR/bin/link_claude_dir.sh" --cloud || failed=1

exit "$failed"
