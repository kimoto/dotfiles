#!/bin/bash

# How many times was each command typed lately, on this machine?
#
# Reads the usage log the .zshrc preexec hook keeps (one command name per
# line, one file per local day) and counts it. The log holds names only, so
# this output does too: it is safe to hand to a scout as it is, but it still
# shows every tool a machine uses, so it goes to private places only.
#
# Usage: usage_counts.sh [--days N | --all]
#   --days N  the last N days, today included (default 7)
#   --all     everything logged
# Output: a line saying which days were read, then <count>\t<name>, most used
# first, ties by name.
#
# Env: XDG_STATE_HOME (the log is $XDG_STATE_HOME/dotfiles/usage, as in
# .zshrc); USAGE_LOG_DIR overrides the whole path (tests);
# USAGE_COUNTS_TODAY (YYYY-MM-DD, tests).

set -euo pipefail

LOG_DIR="${USAGE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/usage}"

days=7
case "${1:-}" in
    --all) days=0 ;;
    --days)
        days="${2:-}"
        if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
            echo "usage_counts: --days takes a whole number of days, 1 or more" >&2
            exit 2
        fi
        ;;
    "") ;;
    *) echo "usage: usage_counts.sh [--days N | --all]" >&2; exit 2 ;;
esac

if [ ! -d "$LOG_DIR" ]; then
    echo "usage_counts: no usage log yet: $LOG_DIR" >&2
    exit 1
fi

# Days are picked by file name, not mtime: a file name is the day it holds,
# whatever a backup or a copy did to its timestamps. macOS date has no -d, so
# the first day is worked out with whichever form this date understands.
first=""
if [ "$days" -gt 0 ]; then
    today="${USAGE_COUNTS_TODAY:-$(date +%Y-%m-%d)}"
    back=$((days - 1))
    first=$(date -d "$today -$back days" +%Y-%m-%d 2>/dev/null ||
        date -j -v-"$back"d -f %Y-%m-%d "$today" +%Y-%m-%d)
fi

files=()
for f in "$LOG_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].log; do
    [ -e "$f" ] || continue
    day=$(basename "$f" .log)
    [[ -z "$first" || ! "$day" < "$first" ]] && files+=("$f")
done

if [ "${#files[@]}" -eq 0 ]; then
    echo "# no days logged${first:+ since $first}"
    exit 0
fi

echo "# $(basename "${files[0]}" .log) to $(basename "${files[${#files[@]} - 1]}" .log), ${#files[@]} days logged"
export LC_ALL=C
cat "${files[@]}" | sort | uniq -c | sort -k1,1nr -k2,2 | awk '{ printf "%d\t%s\n", $1, $2 }'
