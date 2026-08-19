#!/bin/bash
# Measure Neovim startup with this repo's config, and show what the time went
# into. Deliberately NOT wired into CI or lefthook: a wall-clock budget on a
# shared runner is a flake source. This is the tool you run by hand after
# adding a plugin, so "it feels slower" can be answered with a number.
#
# Usage:  ./bin/nvim_startuptime.sh [runs]        (default 5)
#
# Reports the median total, then the slowest entries by SELF time (third
# column of --startuptime) so a heavy module is not hidden inside its parent's
# cumulative figure.
#
# Startup is measured against the plugin tree of the CURRENT user
# (~/.local/share/nvim), i.e. what you actually start every day. Only the
# config dir is redirected at this repo, so an unlinked checkout can be
# measured without running mklink.sh first.
set -euo pipefail

die() { echo "x $*" >&2; exit 1; }

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v nvim >/dev/null 2>&1 || die "nvim not installed"
BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
[ -f "$BASE_DIR/config/nvim/init.lua" ] || die "no config/nvim/init.lua in $BASE_DIR"

RUNS="${1:-5}"
[ "$RUNS" -ge 1 ] 2>/dev/null || die "runs must be a positive integer, got: $RUNS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Point only XDG_CONFIG_HOME at this repo; data/state stay the real ones so the
# installed plugin tree is the one being measured.
export XDG_CONFIG_HOME="$TMP/.config"
mkdir -p "$XDG_CONFIG_HOME"
ln -s "$BASE_DIR/config/nvim" "$XDG_CONFIG_HOME/nvim"
# No background installs racing the measurement.
export DOTFILES_NO_NVIM_AUTO_INSTALL=1

echo "== $(nvim --version | head -1) =="
totals=()
for i in $(seq 1 "$RUNS"); do
  nvim --headless --startuptime "$TMP/st.$i" -c 'qall!' </dev/null >/dev/null 2>&1 ||
    die "nvim exited non-zero during run $i"
  # The last line is the "--- NVIM STARTED ---" marker; the file may end with a
  # blank line, so match the marker rather than reading the final record.
  t="$(awk '/NVIM STARTED/ {t=$1} END {print t}' "$TMP/st.$i")"
  [ -n "$t" ] || die "no timing written for run $i"
  totals+=("$t")
  printf 'run %d: %s ms\n' "$i" "$t"
done

median="$(printf '%s\n' "${totals[@]}" | sort -g | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
echo "median: $median ms"

# Slowest by self time. --startuptime lines with three leading numbers are
# "clock, cumulative, self: what" — the third is time spent in that entry
# alone.
echo
echo "== slowest entries (self time, from run $RUNS) =="
grep -E '^[0-9.]+ +[0-9.]+ +[0-9.]+: ' "$TMP/st.$RUNS" |
  sort -k3 -gr | head -15 |
  awk '{ self=$3; sub(/:$/, "", self); $1=""; $2=""; $3=""; sub(/^ +/, "");
         printf "%8s ms  %s\n", self, $0 }'
