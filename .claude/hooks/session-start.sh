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

# The same script the Setup script field at claude.ai/code calls.
"$REPO/bin/setup_cloud_session.sh" \
  || echo "[session-start] a MISS above did not land — those rules, skills or hooks will not load"

echo "[session-start] tooling ready (bin/setup_cloud_session.sh)"
