#!/bin/bash

# A tool in mise's config that is not installed is re-resolved on every precmd,
# so it taxes each prompt and says nothing: the shell just feels slow.
# DOTFILES_NO_MISE_CHECK is CI's way out, so the load test stays quiet.

set -u

[ -n "${DOTFILES_NO_MISE_CHECK:-}" ] && exit 0

command -v mise >/dev/null 2>&1 || exit 0

# No subprocesses here: a fork is paid before the prompt can render.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
result="$cache_dir/mise_missing"

[ -s "$result" ] && cat "$result" >&2

# Every fd is detached below, or zsh startup and bats' fd 3 wait on this job.
(
    mkdir -p "$cache_dir" 2>/dev/null || true

    tmp="$result.tmp.$$"
    : >"$tmp" 2>/dev/null || exit 0

    # A mise too old for --missing prints nothing, which reads as healthy.
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

    # Atomic: a shell reading mid-write must not see a torn file.
    mv -f "$tmp" "$result" 2>/dev/null || rm -f "$tmp" 2>/dev/null
) >/dev/null 2>&1 3>&- </dev/null &

exit 0
