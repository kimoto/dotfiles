#!/bin/bash

# How many times was each command typed lately, on this machine?
#
# Reads the usage log the .zshrc preexec hook keeps (one command per line:
# its name, and for some tools the subcommand and option names; one file per
# local day) and counts it. The log holds no values, so this output does not
# either: it is safe to hand to a scout as it is, but it still
# shows every tool a machine uses, so it goes to private places only.
# The log is kept only where DOTFILES_USAGE_LOG=1; elsewhere this says so, so
# an empty count is not read as "nothing was used".
#
# Usage: usage_counts.sh [--days N | --all] [--names]
#   --days N  the last N days, today included (default 7)
#   --all     everything logged
#   --names   count by command name alone (`git log` and `git push` as `git`)
# Output: a line saying which days were read, then <count>\t<command>, most
# used first, ties by command.
#
# Env: XDG_STATE_HOME (the log is $XDG_STATE_HOME/dotfiles/usage, as in
# .zshrc); USAGE_LOG_DIR overrides the whole path (tests);
# USAGE_COUNTS_TODAY (YYYY-MM-DD, tests).

set -euo pipefail

LOG_DIR="${USAGE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/usage}"

USAGE="usage: usage_counts.sh [--days N | --all] [--names]"
days=7
names_only=0
window=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --all | --days)
            [ -z "$window" ] || { echo "$USAGE" >&2; exit 2; }
            window=$1
            ;;
    esac
    case "$1" in
        --all) days=0 ;;
        --days)
            days="${2:-}"
            if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                echo "usage_counts: --days takes a whole number of days, 1 or more" >&2
                exit 2
            fi
            shift
            ;;
        --names) names_only=1 ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
    shift
done

if [ "${DOTFILES_USAGE_LOG:-}" != 1 ]; then
    echo "usage_counts: the usage log is off here (DOTFILES_USAGE_LOG is not 1)" >&2
fi

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
if [ "$names_only" -eq 1 ]; then
    cat "${files[@]}" | cut -d' ' -f1
else
    cat "${files[@]}"
fi | sort | uniq -c | sort -k1,1nr -k2 |
    awk '{ n = $1; sub(/^ *[0-9]+ /, ""); printf "%d\t%s\n", n, $0 }'
