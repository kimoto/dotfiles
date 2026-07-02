#!/bin/bash

# Enable weekly, unattended background Homebrew upgrades on macOS.
#
# Uses the homebrew/autoupdate tap, which installs a launchd agent that runs
# `brew update` + `brew upgrade` + `brew cleanup` on a fixed interval, in the
# background, and surfaces a native macOS notification when it runs — no shell
# nag at login. Idempotent: re-running while it's already scheduled is a no-op.
#
# Deliberately NOT passing --sudo: a cask that needs an admin password can't be
# answered by an unattended job, so without --sudo such a cask is simply skipped
# (logged), never hangs. Upgrade your casks by hand (`brew upgrade --cask`) when
# you're at the keyboard. Formulae live under the user-owned brew prefix and
# never need sudo.
#
# launchd is macOS-only, so this is a no-op elsewhere.

set -eu

# Weekly. brew autoupdate takes the interval in seconds.
INTERVAL="${BREW_AUTOUPDATE_INTERVAL:-604800}"

if [ "$(uname)" != "Darwin" ]; then
    echo "brew autoupdate relies on launchd; skipping on non-macOS." >&2
    exit 0
fi

BREW_BIN="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW_BIN" ]; then
    for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$cand" ]; then
            BREW_BIN="$cand"
            break
        fi
    done
fi
if [ -z "$BREW_BIN" ]; then
    echo "brew not found; skipping autoupdate setup." >&2
    exit 0
fi

# Make sure the tap providing the `autoupdate` subcommand is present.
"$BREW_BIN" tap homebrew/autoupdate >/dev/null 2>&1 || true

# Already scheduled? Leave it untouched so this stays idempotent.
if "$BREW_BIN" autoupdate status 2>/dev/null | grep -Eqi 'and running|are enabled'; then
    echo "brew autoupdate already running; nothing to do."
    exit 0
fi

# Start it: update + upgrade (formulae, plus non-greedy casks) + cleanup, weekly,
# with a macOS notification (notifications are on by default). No --sudo on
# purpose (see header).
"$BREW_BIN" autoupdate start "$INTERVAL" --upgrade --cleanup
echo "brew autoupdate started: every $INTERVAL s, background upgrade + cleanup."
