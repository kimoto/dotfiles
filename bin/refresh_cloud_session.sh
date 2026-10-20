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
# The commit this session started from, kept by the first run (the hook):
# rules and settings were read from it, so what moved since is what is stale.
# Before the pull, as rules may load either side of the hook; a superset only
# costs a re-read.
SESSION_BASE=$(git -C "$BASE_DIR" rev-parse --path-format=absolute \
  --git-path refresh-session-base 2>/dev/null)

if [ -z "${REFRESH_CLOUD_PULLED:-}" ]; then
  # main only: a session working on a branch in this checkout owns its HEAD.
  branch=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null)
  if [ -n "$SESSION_BASE" ] && [ ! -e "$SESSION_BASE" ]; then
    git -C "$BASE_DIR" rev-parse HEAD >"$SESSION_BASE" 2>/dev/null
  fi
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

# Rules load once, so the skill re-reads these; Claude Code reloads settings
# itself on change, bar a few keys and the SessionStart hook that already ran.
base=$(cat "$SESSION_BASE" 2>/dev/null)
if [ -n "$base" ]; then
  git -C "$BASE_DIR" diff --no-renames --name-status "$base" HEAD -- \
    claudecode/rules claudecode/rules-cloud claudecode/settings-cloud.json |
  while read -r st path; do
    case "$path:$st" in
      *.json:*) echo "[refresh] settings changed: $path" ;;
      *:D) echo "[refresh] rule removed: $BASE_DIR/$path" ;;
      *) echo "[refresh] rule changed: $BASE_DIR/$path" ;;
    esac
  done
fi

exec "$BASE_DIR/bin/link_claude_dir.sh" --cloud
