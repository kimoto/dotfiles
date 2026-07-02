#!/bin/sh
# Emit an eval-able `export LS_COLORS=...` for _evalcache (see
# config/sheldon/plugins.toml). vivid prints a raw value, not shell code, so
# this wrapper is what lets the palette ride the same cache as the other slow
# inits. Refresh after updating vivid or changing the theme: _evalcache_clear.
set -eu
printf "export LS_COLORS='%s'\n" "$(vivid generate solarized-dark)"
