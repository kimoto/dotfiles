#!/bin/bash

# Report known vulnerabilities in what the tracked lockfiles pull in: the
# uv.lock files mise writes for its pipx: tools, and Hammerspoon's
# requirements.txt. Renovate bumps the top-level versions; nothing else looks
# at the packages underneath them.
#
# CI only, not lefthook: it asks api.osv.dev, so it needs the network, and a
# new advisory turns it red with no change on the branch. A hook that fails on
# work it did not touch is a hook people skip with --no-verify.
#
# An advisory with no fixed release yet can be waived in osv-scanner.toml next
# to the lockfile, with a reason; see osv-scanner's docs on ignored vulns.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_collect '*uv.lock' '*requirements.txt' --

[ "${#files[@]}" -eq 0 ] && exit 0

lint_require osv-scanner

args=()
for f in "${files[@]}"; do
    args+=(-L "$f")
done
osv-scanner scan source "${args[@]}"
