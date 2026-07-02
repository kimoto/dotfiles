#!/bin/bash
# Claude Code on the web — SessionStart hook.
#
# Provisions this repo's lint toolchain in the ephemeral web sandbox so commits
# (lefthook) and the bin/ lint scripts behave the same as in CI. The pinned tool
# versions live in bin/install_check_tools.sh (shared with CI) — NOT duplicated
# here.
#
# Local (non-remote) sessions are skipped: on a real machine `brew bundle` /
# bin/mkworld.sh already set everything up.
set -euo pipefail

# Only run inside the remote web sandbox.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

REPO="${CLAUDE_PROJECT_DIR:-$PWD}"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# 1. Shared lint toolchain (zsh, shellcheck, yq, gitleaks, ratchet, lefthook —
#    versions pinned in bin/install_check_tools.sh, the single source of truth).
"$REPO/bin/install_check_tools.sh"

# 2. Install the git hooks so commits run CI's checks.
if cd "$REPO"; then
  lefthook install >/dev/null 2>&1 || true
fi

# 3. fzf — used by the repo's interactive zsh helpers (g, b, livegrep, ...).
if ! command -v fzf >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get install -y -qq fzf >/dev/null || true
fi

echo "[session-start] tooling ready (bin/install_check_tools.sh + lefthook + fzf)"
