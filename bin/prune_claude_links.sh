#!/bin/sh
# Takes down links in ~/.claude/skills and ~/.claude/agents that point into
# this checkout's claudecode/ but whose target is gone: a skill or agent moved
# out of the repo would otherwise linger as a broken link on every machine.
# Shared by mklink.sh (workstation) and link_claude_dir.sh (cloud).
#
# Usage: prune_claude_links.sh <claude dir>

set -u

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CLAUDE_DIR="$1"

for kind in skills agents; do
    for link in "$CLAUDE_DIR/$kind"/*; do
        [ -L "$link" ] || continue
        [ -e "$link" ] && continue
        # Only ours: a broken link another tool left points somewhere else.
        case "$(readlink "$link")" in
            "$BASE_DIR/claudecode/$kind"/*) rm -f "$link" ;;
        esac
    done
done
