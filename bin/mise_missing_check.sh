#!/bin/bash

# A tool in mise's config that is not installed is re-resolved on every precmd,
# so it taxes each prompt and says nothing: the shell just feels slow. The same
# background run also warns when this mise is not the release CI pins.
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

    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'

    # A mise too old for --missing prints nothing, which reads as healthy.
    missing=$(mise ls --missing 2>/dev/null | grep -c . || true)

    if [ "${missing:-0}" -gt 0 ] 2>/dev/null; then
        printf '%s[mise]%s %s tool(s) in config but not installed,' \
            "$yellow" "$reset" "$missing" >>"$tmp"
        printf ' and every prompt pays to look for them -> %smise install%s\n' \
            "$cyan" "$reset" >>"$tmp"
    fi

    # CI runs the mise pinned in install_check_tools.sh; a workstation's moves
    # with Homebrew. Two releases write mise.lock's pipx entries differently,
    # so a drift shows up later as a dirty checkout or a red `--locked` in CI.
    pin_file="$(dirname "$(readlink -f "$0")")/install_check_tools.sh"
    pin=$(sed -n 's/^MISE_VERSION=.*:-\([^}]*\)}.*/\1/p' "$pin_file" 2>/dev/null)
    have=$(mise --version 2>/dev/null | awk 'NR == 1 { print $1 }')
    if [ -n "$pin" ] && [ -n "$have" ] && [ "$have" != "$pin" ]; then
        printf '%s[mise pin]%s %s here, %s in CI (bin/install_check_tools.sh):' \
            "$yellow" "$reset" "$have" "$pin" >>"$tmp"
        printf ' a mise.lock written here may fail CI'"'"'s --locked\n' >>"$tmp"
    fi

    # Atomic: a shell reading mid-write must not see a torn file.
    mv -f "$tmp" "$result" 2>/dev/null || rm -f "$tmp" 2>/dev/null
) >/dev/null 2>&1 3>&- </dev/null &

exit 0
