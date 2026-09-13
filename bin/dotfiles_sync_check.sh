#!/bin/bash

# Warns at shell startup that this repo needs syncing between machines.
#
# ⚠ What it prints is the previous shell's answer, and "behind" lags up to one
# 24h fetch window on top of that — never read it as the state right now.
#
# DOTFILES_NO_SYNC_CHECK skips it: the load test must not reach the network.

set -u

[ -n "${DOTFILES_NO_SYNC_CHECK:-}" ] && exit 0

# Path-only, no subprocesses: every fork here is paid before an interactive
# shell can draw its prompt, and on an EDR-managed mac an exec costs far more
# than the work it does.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
fetch_stamp="$cache_dir/last_fetch"
result="$cache_dir/sync_status"

[ -s "$result" ] && cat "$result" >&2

# Every fd detached, or zsh startup and bats' fd 3 wait on this job.
(
    REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd) || exit 0
    mkdir -p "$cache_dir" 2>/dev/null || true

    git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'

    tmp="$result.tmp.$$"
    : >"$tmp" 2>/dev/null || exit 0

    note() {
        printf '%s[dotfiles]%s %s -> %s%s%s\n' \
            "$yellow" "$reset" "$1" "$cyan" "$2" "$reset" >>"$tmp"
    }

    if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
        note "uncommitted changes" "git -C $REPO_DIR add -A && git -C $REPO_DIR commit"
    fi

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

    # Atomic: a shell reading mid-write would otherwise see a torn file.
    mv -f "$tmp" "$result" 2>/dev/null || rm -f "$tmp" 2>/dev/null

    # After the status write, so a slow network never delays the next shell.
    # The stamp is written only on success: an offline machine keeps retrying.
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
        git -C "$REPO_DIR" fetch --quiet --prune 2>/dev/null \
            && date +%s >"$fetch_stamp" 2>/dev/null
    fi
) >/dev/null 2>&1 3>&- </dev/null &

exit 0
