#!/bin/bash
# Claude Code on the web — SessionStart hook.
#
# Local (non-remote) sessions are skipped: mkworld.sh already set that machine up.
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
