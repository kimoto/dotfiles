#!/bin/bash

# dotfiles sync reminder.
#
# Warns at shell startup when the dotfiles repo needs syncing between machines
# (e.g. home and office), which is easy to forget:
#   - uncommitted changes        -> forgot to commit
#   - committed but unpushed      -> forgot to push
#   - upstream has new commits    -> forgot to pull
#
# Local state (dirty / ahead) is checked every time because it is cheap.
# Remote state (behind) relies on the remote-tracking ref, which is refreshed
# by a background `git fetch` at most once per 24h so shell startup is never
# blocked on the network. The "behind" warning can therefore be one session
# stale, which is an acceptable trade-off for instant startup.
#
# Skipped entirely when DOTFILES_NO_SYNC_CHECK is set (used by CI so the load
# test neither touches the network nor prints reminder noise).

set -u

[ -n "${DOTFILES_NO_SYNC_CHECK:-}" ] && exit 0

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd) || exit 0

# Only proceed inside a git work tree.
git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$cache_dir" 2>/dev/null || true
fetch_stamp="$cache_dir/last_fetch"

# Refresh the remote-tracking ref at most once per 24h, in the background.
need_fetch=1
if [ -f "$fetch_stamp" ]; then
    last=$(cat "$fetch_stamp" 2>/dev/null || echo 0)
    case "$last" in
        '' | *[!0-9]*) last=0 ;;
    esac
    if [ "$(( $(date +%s) - last ))" -lt 86400 ]; then
        need_fetch=0
    fi
fi
if [ "$need_fetch" -eq 1 ]; then
    # Stamp is written only on success so an offline machine keeps retrying.
    ( git -C "$REPO_DIR" fetch --quiet --prune 2>/dev/null \
        && date +%s >"$fetch_stamp" 2>/dev/null ) &
fi

yellow=$'\033[33m'
cyan=$'\033[36m'
reset=$'\033[0m'

note() {
    # $1: message, $2: suggested command
    printf '%s[dotfiles]%s %s -> %s%s%s\n' \
        "$yellow" "$reset" "$1" "$cyan" "$2" "$reset" >&2
}

# 1) Uncommitted changes (forgot to commit).
if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
    note "uncommitted changes" "git -C $REPO_DIR add -A && git -C $REPO_DIR commit"
fi

# 2) Unpushed commits / 3) behind upstream (forgot to push / pull).
if git -C "$REPO_DIR" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    counts=$(git -C "$REPO_DIR" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo '')
    behind=$(printf '%s' "$counts" | awk '{print $1}')
    ahead=$(printf '%s' "$counts" | awk '{print $2}')
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
        note "${ahead} unpushed commit(s)" "git -C $REPO_DIR push"
    fi
    if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
        note "${behind} commit(s) behind upstream" "git -C $REPO_DIR pull"
    fi
fi

exit 0
