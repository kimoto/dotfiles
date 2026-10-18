#!/bin/bash
# The tmux e2e checks, run against whichever tmux is on PATH. Both the cached
# old tmux job and the latest-release job in ci.yml call this, so a new check
# added here runs on both.
#
# Every check runs even after one fails, so a single CI run reports them all.

set -uo pipefail

E2E="$(cd "$(dirname "$(readlink -f "$0")")/../test/e2e" && pwd)"

failed=()
for t in \
    tmux_loading_test.sh \
    tmux_interactive_test.sh \
    tmux_keybinding_test.sh \
    tmux_copymode_test.sh \
    tmux_status_test.sh \
    claude_tmux_indicator_test.sh \
    claude_tmux_hunk_test.sh \
    keys_command_test.sh; do
    echo "::group::$t"
    "$E2E/$t" || failed+=("$t")
    echo "::endgroup::"
done

if [ "${#failed[@]}" -gt 0 ]; then
    echo "::error::failed: ${failed[*]}"
    exit 1
fi
