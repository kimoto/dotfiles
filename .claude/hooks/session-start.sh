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
LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-2.1.9}"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# 1. Shared lint toolchain (zsh, shellcheck, yq, gitleaks, ratchet).
"$REPO/bin/install_check_tools.sh"

# 2. lefthook — git hook runner; install hooks so commits run CI's checks.
if ! command -v lefthook >/dev/null 2>&1; then
  curl -sSfL "https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION}_Linux_x86_64.gz" \
    | gunzip > /tmp/lefthook
  as_root install -m 0755 /tmp/lefthook /usr/local/bin/lefthook
  rm -f /tmp/lefthook
fi
if cd "$REPO"; then
  lefthook install >/dev/null 2>&1 || true
fi

# 3. fzf — used by the repo's interactive zsh helpers (g, b, livegrep, ...).
if ! command -v fzf >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get install -y -qq fzf >/dev/null || true
fi

echo "[session-start] tooling ready (bin/install_check_tools.sh + lefthook + fzf)"
