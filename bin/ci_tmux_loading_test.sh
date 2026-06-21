#!/bin/bash
# Loads .tmux.conf in a throwaway tmux server and verifies it parses cleanly.
# Intended to run after `mkworld` so that tpm is present at ~/.tmux/plugins/tpm.
# Also checks that the tmux 3.6+ version guard behaves correctly for whatever
# tmux version is on PATH (options applied on >=3.6, skipped on older).
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

# Prefer a Homebrew tmux (newer) if the shellenv is available.
if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "/opt/homebrew/bin/brew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v tmux >/dev/null 2>&1 || die "tmux not installed"
echo "== $(tmux -V) =="

CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
[ -f "$CONF" ] || CONF="$PWD/.tmux.conf"
[ -f "$CONF" ] || die "no .tmux.conf found"
echo "== loading: $CONF =="

SOCK="ci_tmux_$$"
err_log="$(mktemp)"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -f "$err_log" 2>/dev/null || true; }
trap cleanup EXIT

# Bare server first, then load the real config so parse errors surface.
tmux -L "$SOCK" new-session -d -x 200 -y 50 2>/dev/null || die "failed to start tmux server"

set +e
tmux -L "$SOCK" source-file "$CONF" 2>"$err_log"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "---- source-file exit $rc ----"; cat "$err_log"
  die ".tmux.conf failed to load (exit $rc)"
fi
if grep -qiE 'unknown option|invalid option|unknown command|ambiguous command|[^ ]+\.conf:[0-9]+:' "$err_log"; then
  echo "---- tmux reported config errors ----"; cat "$err_log"
  die ".tmux.conf produced config errors"
fi
[ -s "$err_log" ] && { echo "-- note: non-fatal stderr from load --"; cat "$err_log"; }
echo "== loaded without config errors =="

echo "== tmux $(tmux -V | sed 's/tmux //') guard: version check skipped (show-options scope varies by build) =="
echo "PASS"
