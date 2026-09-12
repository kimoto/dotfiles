#!/bin/bash

# mise missing-tool reminder.
#
# A tool in mise's config that is not installed makes mise re-resolve it on
# every precmd, so the cost lands on each prompt rather than once at startup.
# Nothing reports it: the shell just feels slow, and the state is reachable
# from ordinary paths — mklink.sh before `mise install`, an install that failed
# partway, a machine set up last month and never finished.
#
# Notify-only, never installs. Same shape as dotfiles_sync_check.sh: the
# foreground prints the cached result of the previous run and a detached
# background job recomputes it, so a warning can be one shell stale. No
# throttle — the check is cheap when healthy, and while tools are missing the
# nag has to survive until they are installed.
#
# Skipped entirely when DOTFILES_NO_MISE_CHECK is set (used by CI so the load
# test neither slows down nor prints reminder noise).

set -u

[ -n "${DOTFILES_NO_MISE_CHECK:-}" ] && exit 0

# mise not installed yet -> stay silent; bootstrap (bin/mkworld.sh) handles that.
command -v mise >/dev/null 2>&1 || exit 0

# Path-only, no subprocesses: every fork here is paid by an interactive shell
# before it can draw a prompt.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
result="$cache_dir/mise_missing"

#---------------------------------------------------------------
# foreground: print the cached result and get out of the way
#---------------------------------------------------------------
[ -s "$result" ] && cat "$result" >&2

#---------------------------------------------------------------
# background: refresh the cache for the next shell
#---------------------------------------------------------------
# All fds are detached so neither the terminal nor the caller (zsh startup, or
# bats' fd 3) ever waits on this job.
(
    mkdir -p "$cache_dir" 2>/dev/null || true

    tmp="$result.tmp.$$"
    : >"$tmp" 2>/dev/null || exit 0

    # A mise too old for `--missing` errors out and prints nothing, which leaves
    # the cache empty and this silent — the same as healthy, and the safe way
    # round.
    missing=$(mise ls --missing 2>/dev/null | grep -c . || true)

    if [ "${missing:-0}" -gt 0 ] 2>/dev/null; then
        yellow=$'\033[33m'
        cyan=$'\033[36m'
        reset=$'\033[0m'
        printf '%s[mise]%s %s tool(s) in config but not installed,' \
            "$yellow" "$reset" "$missing" >>"$tmp"
        printf ' and every prompt pays to look for them -> %smise install%s\n' \
            "$cyan" "$reset" >>"$tmp"
    fi

    # Replaced atomically so a shell reading mid-write never sees a torn file.
    mv -f "$tmp" "$result" 2>/dev/null || rm -f "$tmp" 2>/dev/null
) >/dev/null 2>&1 3>&- </dev/null &

exit 0
