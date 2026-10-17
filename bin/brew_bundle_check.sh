#!/bin/bash

# Brewfile drift reminder.
#
# Warns at shell startup when a Brewfile bundle is not satisfied — a package it
# lists is missing, or an installed one is out of date — so the tools you expect
# are present and current. `brew bundle check` does not distinguish the two and
# `brew bundle install` fixes either, which is what the printed command does.
# Notify-only: this script never installs anything.
#
# Where the brew_auto_upgrade.sh agent is installed and has succeeded recently,
# drift made only of homebrew/core formulae is left to it and not reported;
# casks and third-party taps still are, since those stay manual. Once the agent
# has not succeeded for a while, the nag is about the agent instead.
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

# Path-only, no subprocesses: every fork here is paid by an interactive shell
# before it can draw a prompt, and on an EDR-managed mac an exec costs far more
# than the work it does. Resolving the repo root, picking the platform Brewfile
# and creating the cache dir all run commands, so they are deferred: the repo
# root is resolved lazily (only when there is actually a warning to print), the
# rest happens inside the background job.
resolve_repo_dir() {
    REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd)
}

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
stamp="$cache_dir/last_brew_check"
result="$cache_dir/brew_missing"
auto_stamp="$cache_dir/brew_auto_upgrade_ok"
auto_plist="$HOME/Library/LaunchAgents/local.dotfiles.brew-auto-upgrade.plist"
auto_log="$HOME/Library/Logs/dotfiles/brew_auto_upgrade.log"

#---------------------------------------------------------------
# foreground: print the cached result and get out of the way
#---------------------------------------------------------------
if [ -s "$result" ]; then
    resolve_repo_dir || exit 0

    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'

    # One line per unsatisfied Brewfile, with a ready-to-run install command.
    listed=0
    while IFS= read -r f; do
        case "$f" in
            '') ;;
            '!stale '*)
                printf '%s[brew]%s daily formula auto-upgrade has not succeeded since %s -> %stail %s%s\n' \
                    "$yellow" "$reset" "${f#!stale }" "$cyan" "$auto_log" "$reset" >&2
                ;;
            *)
                listed=1
                printf '%s[brew]%s %s has missing or outdated packages -> %sbrew bundle install --file=%s/%s%s\n' \
                    "$yellow" "$reset" "$f" "$cyan" "$REPO_DIR" "$f" "$reset" >&2
                ;;
        esac
    done <"$result"
    # One-shot alternative that installs everything and batches the prompts.
    if [ "$listed" -eq 1 ]; then
        printf '%s[brew]%s or install all at once -> %s%s/bin/brew_bundle_install.sh%s\n' \
            "$yellow" "$reset" "$cyan" "$REPO_DIR" "$reset" >&2
    fi
fi

#---------------------------------------------------------------
# background: refresh the cache for the next shell
#---------------------------------------------------------------
# All fds are detached so neither the terminal nor the caller (zsh startup, or
# bats' fd 3) ever waits on this job.
(
    resolve_repo_dir || exit 0
    mkdir -p "$cache_dir" 2>/dev/null || true

    # Brewfiles to check: shell-load essentials + full workstation + this platform.
    files=(Brewfile.standard Brewfile.extra)
    case "$(uname)" in
        Darwin) files+=(Brewfile.macos) ;;
        Linux) files+=(Brewfile.linux) ;;
    esac

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

    # The agent counts as working for 3 days after its last success: it runs
    # daily, and a machine left off over a weekend has not missed anything.
    auto_fresh=0
    stale_since=""
    if [ -f "$auto_plist" ]; then
        auto_last=$(cat "$auto_stamp" 2>/dev/null || echo 0)
        case "$auto_last" in
            '' | *[!0-9]*) auto_last=0 ;;
        esac
        if [ "$(( $(date +%s) - auto_last ))" -lt 259200 ]; then
            auto_fresh=1
        elif [ "$auto_last" -eq 0 ]; then
            stale_since="never"
        else
            stale_since=$(date -r "$auto_last" '+%Y-%m-%d' 2>/dev/null \
                || date -d "@$auto_last" '+%Y-%m-%d' 2>/dev/null || echo "$auto_last")
        fi
    fi

    missing=()
    [ -n "$stale_since" ] && missing+=("!stale $stale_since")
    for f in "${files[@]}"; do
        [ -f "$REPO_DIR/$f" ] || continue
        out=$(brew bundle check --verbose --file="$REPO_DIR/$f" 2>&1) && continue
        # --verbose lists every unmet entry as "→ <Type> <name> needs ...".
        # Only homebrew/core formulae (no slash in the name) are the agent's;
        # an empty list means the check failed for some other reason.
        unmet=$(printf '%s\n' "$out" | grep '^→ ')
        if [ "$auto_fresh" -eq 1 ] && [ -n "$unmet" ] \
            && ! printf '%s\n' "$unmet" | grep -qv '^→ Formula [^/ ]* needs'; then
            continue
        fi
        missing+=("$f")
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
