#!/bin/bash
# Loads .tmux.conf in a throwaway tmux server and verifies it parses cleanly.
# Intended to run after `mkworld` so that tpm is present at ~/.tmux/plugins/tpm.
# Also checks that the version guards still apply when the server was started
# with a PATH that lacks the tmux binary's directory.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
echo "== loading: $CONF =="

SOCK="ci_tmux_$$"
BARE_SOCK="${SOCK}_bare"
err_log="$(mktemp)"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  tmux -L "$BARE_SOCK" kill-server 2>/dev/null || true
  rm -f "$err_log" 2>/dev/null || true
}
trap cleanup EXIT

# Bare server first, then load the real config so parse errors surface.
tmux -L "$SOCK" new-session -d -x 200 -y 50 2>/dev/null || die "failed to start tmux server"

# Load-time budget. Observed: ~100ms on a local Linux box, ~510ms on a shared
# GitHub runner (slower CPU + tpm/plugin sourcing), so 1000ms only trips on a
# real regression (e.g. a load-time #()/run-shell or network call sneaking in,
# which costs seconds). Overridable for tuning/testing via TMUX_LOAD_BUDGET_MS.
LOAD_BUDGET_MS="${TMUX_LOAD_BUDGET_MS:-1000}"
# macOS `date` lacks %N, so use perl for portable millisecond timestamps.
need perl
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }

start_ms="$(now_ms)"
set +e
tmux -L "$SOCK" source-file "$CONF" 2>"$err_log"
rc=$?
set -e
end_ms="$(now_ms)"

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
# The config just armed @continuum-restore 'on'; disarm it before it restores
# the saved session into this scratch server (see disable_continuum_restore).
disable_continuum_restore "$SOCK"

load_ms=$((end_ms - start_ms))
echo "== load time: ${load_ms}ms (budget: ${LOAD_BUDGET_MS}ms) =="
if [ "$load_ms" -gt "$LOAD_BUDGET_MS" ]; then
  echo "---- load-time budget exceeded ----"
  echo "NOTE: timing on shared CI runners fluctuates. If this budget check is"
  echo "the ONLY failure, re-run the job once before investigating — treat a"
  echo "single overrun as flaky. Only a failure that reproduces on re-run is"
  echo "a real regression; then look for load-time #()/run-shell additions in"
  echo "recent .tmux.conf changes."
  die ".tmux.conf took ${load_ms}ms to load (budget: ${LOAD_BUDGET_MS}ms)"
fi

# Version guards must hold on a server started with a bare PATH: Ghostty starts
# tmux through `zsh -l -c`, which never reads .zshrc, so Homebrew's bin is not
# on the server's PATH. prefix + a is bound only behind the 3.7 guard.
TMUX_BIN="$(command -v tmux)"
# Loaded at startup with -f, as Ghostty's server is: a later source-file runs
# the guards with the sending client's PATH and passes regardless.
env -i HOME="$HOME" TERM=xterm-256color PATH=/usr/bin:/bin \
  "$TMUX_BIN" -L "$BARE_SOCK" -f "$CONF" new-session -d -x 200 -y 50 2>/dev/null \
  || die "failed to start bare-PATH tmux server"
disable_continuum_restore "$BARE_SOCK"
ver="$(tmux -V | sed -En 's/^tmux (next-)?([0-9]+)\.([0-9]+).*/\2 \3/p')"
# shellcheck disable=SC2086
set -- $ver
if [ "${1:-0}" -gt 3 ] || { [ "${1:-0}" -eq 3 ] && [ "${2:-0}" -ge 7 ]; }; then
  tmux -L "$BARE_SOCK" list-keys -T prefix a >/dev/null 2>&1 \
    || die "3.7 guard skipped on a bare-PATH server: prefix + a is unbound"
  echo "== bare-PATH server: 3.7 guard applied =="
else
  echo "== tmux $(tmux -V | sed 's/tmux //'): older than 3.7, guard correctly skipped =="
fi
echo "PASS"
