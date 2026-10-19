#!/bin/bash
# Brings a cloud session's ~/.claude up to the checkout's newest main: fast-
# forward, then link_claude_dir.sh --cloud. Run by the settings-cloud.json
# SessionStart hook and by the cloud-refresh skill mid-session.
#
# A cloud environment restores the setup script's result from a cache, hook
# text included, and Claude Code reads hooks once at startup. So the hook only
# names this file, and everything after the pull lives here: the re-exec below
# runs the copy the pull just brought in, never the cached one.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

if [ -z "${REFRESH_CLOUD_PULLED:-}" ]; then
  # main only: a session working on a branch in this checkout owns its HEAD.
  branch=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null)
  if [ "$branch" != main ]; then
    echo "[refresh] pull skipped: on '${branch:-detached}', not main"
  elif before=$(git -C "$BASE_DIR" rev-parse --short HEAD) &&
       timeout 10 git -C "$BASE_DIR" pull -q --ff-only >/dev/null 2>&1; then
    echo "[refresh] main: $before -> $(git -C "$BASE_DIR" rev-parse --short HEAD)"
  else
    # Diverged, dirty or offline: the links below still match what is here.
    echo "[refresh] MISS pull: main did not fast-forward"
  fi
  REFRESH_CLOUD_PULLED=1 exec "$BASE_DIR/bin/refresh_cloud_session.sh" "$@"
fi

exec "$BASE_DIR/bin/link_claude_dir.sh" --cloud
