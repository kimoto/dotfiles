#!/bin/bash

# Brewfile drift reminder.
#
# Warns at shell startup when a Brewfile bundle lists packages that aren't
# installed yet — e.g. after adding a formula, or on a freshly bootstrapped
# machine — so the tools you expect are actually present. Notify-only: it never
# installs anything, it just prints the exact `brew bundle install` to run.
#
# `brew bundle check` is comparatively slow, so startup never waits for it: the
# foreground only prints the cached result of the previous check, then a
# detached background job refreshes the cache. An "all satisfied" result is
# trusted for 24h (or until a Brewfile, the Cellar, or the Caskroom changes),
# but a pending warning is re-checked every startup, so installing the missing
# packages clears the nag on the next shell instead of when the 24h throttle
# expires. The warning can therefore be one shell stale — the same trade-off
# dotfiles_sync_check.sh makes for its background `git fetch`.
#
# Skipped entirely when DOTFILES_NO_BREW_CHECK is set (used by CI so the load
# test neither slows down nor prints reminder noise).

set -u

[ -n "${DOTFILES_NO_BREW_CHECK:-}" ] && exit 0

# brew not installed yet -> stay silent; bootstrap (bin/mkworld.sh) handles that.
command -v brew >/dev/null 2>&1 || exit 0

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd) || exit 0

# Brewfiles to check: shell-load essentials + full workstation + this platform.
files=(Brewfile.basic Brewfile.common)
case "$(uname)" in
    Darwin) files+=(Brewfile.macos) ;;
    Linux) files+=(Brewfile.linux) ;;
esac

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$cache_dir" 2>/dev/null || true
stamp="$cache_dir/last_brew_check"
result="$cache_dir/brew_missing"

#---------------------------------------------------------------
# foreground: print the cached result and get out of the way
#---------------------------------------------------------------
if [ -s "$result" ]; then
    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'

    # One line per unsatisfied Brewfile, with a ready-to-run install command.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        printf '%s[brew]%s %s has uninstalled packages -> %sbrew bundle install --file=%s/%s%s\n' \
            "$yellow" "$reset" "$f" "$cyan" "$REPO_DIR" "$f" "$reset" >&2
    done <"$result"
fi

#---------------------------------------------------------------
# background: refresh the cache for the next shell
#---------------------------------------------------------------
# All fds are detached so neither the terminal nor the caller (zsh startup, or
# bats' fd 3) ever waits on this job.
(
    # Re-run the (slow) check at most once per 24h — but only trust a cached
    # "all satisfied" result. A pending warning is re-checked every startup so
    # acting on it clears the nag on the next shell.
    need_check=1
    if [ -f "$stamp" ] && [ -f "$result" ] && [ ! -s "$result" ]; then
        last=$(cat "$stamp" 2>/dev/null || echo 0)
        case "$last" in
            '' | *[!0-9]*) last=0 ;;
        esac
        if [ "$(( $(date +%s) - last ))" -lt 86400 ]; then
            need_check=0
        fi
    fi

    # Invalidate the cache if any Brewfile, the Homebrew Cellar, or the
    # Caskroom changed since the last check.
    if [ "$need_check" -eq 0 ]; then
        cellar=$(brew --cellar 2>/dev/null) || cellar=""
        caskroom=$(brew --caskroom 2>/dev/null) || caskroom=""
        for check_path in "${files[@]/#/$REPO_DIR/}" ${cellar:+"$cellar"} ${caskroom:+"$caskroom"}; do
            [ -e "$check_path" ] || continue
            mtime=$(stat -c %Y "$check_path" 2>/dev/null || stat -f %m "$check_path" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$last" ]; then
                need_check=1
                break
            fi
        done
    fi

    [ "$need_check" -eq 1 ] || exit 0

    # Single-runner lock: a burst of new shells (e.g. tmux restoring panes)
    # must not stampede N parallel `brew bundle check` runs. A leftover lock
    # from a crashed run is stolen after 10 minutes.
    lock="$cache_dir/brew_check.lock"
    if ! mkdir "$lock" 2>/dev/null; then
        lock_mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || echo 0)
        [ "$(( $(date +%s) - lock_mtime ))" -gt 600 ] || exit 0
        rmdir "$lock" 2>/dev/null || true
        mkdir "$lock" 2>/dev/null || exit 0
    fi
    trap 'rmdir "$lock" 2>/dev/null' EXIT

    missing=()
    for f in "${files[@]}"; do
        [ -f "$REPO_DIR/$f" ] || continue
        brew bundle check --file="$REPO_DIR/$f" >/dev/null 2>&1 || missing+=("$f")
    done

    # Persist the unsatisfied Brewfiles (one per line) + a stamp so later logins
    # are free. Written even when empty, so "all satisfied" is also cached, and
    # replaced atomically so a shell reading mid-write never sees a torn file.
    tmp="$result.tmp.$$"
    if [ "${#missing[@]}" -gt 0 ]; then
        printf '%s\n' "${missing[@]}" >"$tmp" 2>/dev/null || exit 0
    else
        : >"$tmp" 2>/dev/null || exit 0
    fi
    mv -f "$tmp" "$result" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    date +%s >"$stamp" 2>/dev/null || true
) >/dev/null 2>&1 3>&- </dev/null &

exit 0
