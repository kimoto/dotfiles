#!/bin/bash
# What a cloud container needs from this repo. Called from the Setup script
# field at claude.ai/code and from the web-sandbox hook — as `... || true`
# there: a non-zero exit fails the whole session, and a step that did not land
# exits non-zero here. Never on a workstation: mkworld.sh owns that machine.

set -uo pipefail

# From this script, never $PWD: a session opened on another repo clones this one
# to the side and never cd's into it — how this checkout came to carry no git
# hooks at all while CI stayed green.
BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

failed=0

# Pinned versions, shared with CI.
if "$BASE_DIR/bin/install_check_tools.sh"; then
  toolchain=1
else
  toolchain=0
  failed=1
fi

# ⚠ Hooks without the toolchain refuse every commit rather than check it: each
# bin/lint_*.sh exits non-zero when the tool it drives is absent.
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
