#!/bin/sh
# Emit an eval-able `export LS_COLORS=...` for _evalcache (see
# config/sheldon/plugins.toml). vivid prints a raw value, not shell code, so
# this wrapper is what lets the palette ride the same cache as the other slow
# inits. Refresh after updating vivid or changing the theme: _evalcache_clear.
set -eu
# Substitute via an assignment: a failing $(vivid ...) inside printf's argument
# list would NOT trip `set -e`, and an empty export would get cached.
colors="$(vivid generate solarized-dark)"
printf "export LS_COLORS='%s'\n" "$colors"
