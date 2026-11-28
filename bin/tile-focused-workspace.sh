#!/bin/sh
# Sets one layout on every window of the focused AeroSpace workspace
# (service mode ⌥+⇧+T / ⌥+⇧+F in .aerospace.toml).
#
# AeroSpace runs this with exec-and-forget, so nobody sees its output. The
# layout is checked before any window is touched: an unknown one would
# otherwise fail once per window and leave the workspace looking unchanged.

set -eu

case "${1:-}" in
    tiling | floating) layout="$1" ;;
    *)
        echo "usage: $(basename "$0") tiling|floating" >&2
        exit 2
        ;;
esac

aerospace list-windows --workspace focused --format '%{window-id}' | xargs -n1 aerospace layout "$layout" --window-id
