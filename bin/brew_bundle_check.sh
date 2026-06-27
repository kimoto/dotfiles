#!/bin/bash

# Brewfile drift reminder.
#
# Warns at shell startup when a Brewfile bundle lists packages that aren't
# installed yet — e.g. after adding a formula, or on a freshly bootstrapped
# machine — so the tools you expect are actually present. Notify-only: it never
# installs anything, it just prints the exact `brew bundle install` to run.
#
# `brew bundle check` is comparatively slow, so it runs at most once per 24h and
# its result is cached; every other login just reads the cached result and is
# effectively free. Same "cheap nag, throttled expensive part" trade-off as
# dotfiles_sync_check.sh, so the "missing" warning can be one day stale.
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

# Re-run the (slow) check at most once per 24h; otherwise reuse the cached list.
need_check=1
if [ -f "$stamp" ] && [ -f "$result" ]; then
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    case "$last" in
        '' | *[!0-9]*) last=0 ;;
    esac
    if [ "$(( $(date +%s) - last ))" -lt 86400 ]; then
        need_check=0
    fi
fi

# Invalidate cache if any Brewfile or the Homebrew Cellar changed since last check.
if [ "$need_check" -eq 0 ]; then
    cellar=$(brew --cellar 2>/dev/null) || cellar=""
    for check_path in "${files[@]/#/$REPO_DIR/}" ${cellar:+"$cellar"}; do
        [ -e "$check_path" ] || continue
        mtime=$(stat -f %m "$check_path" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$last" ]; then
            need_check=1
            break
        fi
    done
fi

if [ "$need_check" -eq 1 ]; then
    missing=()
    for f in "${files[@]}"; do
        [ -f "$REPO_DIR/$f" ] || continue
        brew bundle check --file="$REPO_DIR/$f" >/dev/null 2>&1 || missing+=("$f")
    done
    # Persist the unsatisfied Brewfiles (one per line) + a stamp so later logins
    # are free. Written even when empty, so "all satisfied" is also cached.
    if [ "${#missing[@]}" -gt 0 ]; then
        printf '%s\n' "${missing[@]}" >"$result" 2>/dev/null || true
    else
        : >"$result" 2>/dev/null || true
    fi
    date +%s >"$stamp" 2>/dev/null || true
fi

# Nothing unsatisfied (empty or absent cache) -> stay silent.
[ -s "$result" ] || exit 0

yellow=$'\033[33m'
cyan=$'\033[36m'
reset=$'\033[0m'

# One line per unsatisfied Brewfile, with a ready-to-run install command.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s[brew]%s %s has uninstalled packages -> %sbrew bundle install --file=%s/%s%s\n' \
        "$yellow" "$reset" "$f" "$cyan" "$REPO_DIR" "$f" "$reset" >&2
done <"$result"

exit 0
