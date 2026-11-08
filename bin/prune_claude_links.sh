#!/bin/sh
# Takes down links in ~/.claude/skills and ~/.claude/agents that point into a
# claudecode/ of this repo but whose target is gone: a skill or agent moved out
# of the repo would otherwise linger as a broken link on every machine.
#
# Usage: prune_claude_links.sh <claude dir>

set -u

CLAUDE_DIR="$1"

for kind in skills agents; do
    for link in "$CLAUDE_DIR/$kind"/*; do
        [ -L "$link" ] || continue
        [ -e "$link" ] && continue
        # Any checkout's path counts, as in link_claude_dir.sh: a container can
        # hold two clones. A broken link another tool left points elsewhere.
        case "$(readlink "$link")" in
            */claudecode/"$kind"/*)
                rm -f "$link" || exit 1
                echo "removed broken link: $link"
                ;;
        esac
    done
done
