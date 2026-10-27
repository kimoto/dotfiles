#!/bin/bash

# Which processes used the CPU over a fixed window, from the change in their
# accumulated CPU time. `top`'s instant %CPU swings 10-55% for the same load
# and has misled one diagnosis after another; a 30-second delta does not.
#
#   cpu_window.sh [SECONDS]                 sample twice, SECONDS apart (30)
#   cpu_window.sh --diff BEFORE AFTER SECONDS
#
# BEFORE and AFTER are `ps -Ao pid=,time=,comm=` output; --diff is the pure
# half the tests feed. Output, busiest first:
#
#   core%  machine%  pid  command
#
# core% is per core (one busy core = 100), machine% divides by the core
# count: a process at 50 core% on 8 cores is 6% of the machine, which is
# the number to judge "is this why it is slow" by. A process that started
# inside the window is marked `(new)`; all its CPU time is in the window, so
# its figure is exact. One that exited inside the window is not seen at all.
# A pid whose command changed, or whose time went down, was reused: counted
# as new. Rows under MIN_CORE_PCT (env, default 2) are dropped.

set -euo pipefail

usage() {
    echo "usage: $(basename "$0") [SECONDS] | --diff BEFORE AFTER SECONDS" >&2
    exit 2
}

ncpu() {
    if [ -n "${CPU_WINDOW_NCPU:-}" ]; then
        echo "$CPU_WINDOW_NCPU"
    elif command -v sysctl >/dev/null && sysctl -n hw.ncpu 2>/dev/null; then
        :
    else
        nproc
    fi
}

diff_snapshots() {
    local before=$1 after=$2 seconds=$3
    awk -v secs="$seconds" -v ncpu="$(ncpu)" -v min="${MIN_CORE_PCT:-2}" '
        # [DD-][HH:]MM:SS[.ss] -> seconds
        function tosec(t,   days, n, f, s) {
            days = 0
            if (t ~ /-/) { split(t, d, "-"); days = d[1]; t = d[2] }
            n = split(t, f, ":")
            s = f[n] + f[n - 1] * 60
            if (n == 3) s += f[1] * 3600
            return s + days * 86400
        }
        {
            pid = $1; time = $2
            sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "")
        }
        FNR == NR { t[pid] = tosec(time); c[pid] = $0; next }
        {
            now = tosec(time)
            fresh = !(pid in t) || c[pid] != $0 || now < t[pid]
            used = fresh ? now : now - t[pid]
            pct = used / secs * 100
            if (pct < min) next
            printf "%6.1f\t%6.1f\t%s\t%s%s\n", pct, pct / ncpu, pid, $0, fresh ? "  (new)" : ""
        }
    ' "$before" "$after" | sort -t$'\t' -k1,1 -rn
}

if [ "${1:-}" = "--diff" ]; then
    [ "$#" -eq 4 ] && [ -r "$2" ] && [ -r "$3" ] && [[ $4 =~ ^[0-9]+$ ]] && [ "$4" -gt 0 ] || usage
    diff_snapshots "$2" "$3" "$4"
    exit 0
fi

seconds=${1:-30}
[[ $seconds =~ ^[0-9]+$ ]] && [ "$seconds" -gt 0 ] || usage
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ps -Ao pid=,time=,comm= >"$tmp/before"
sleep "$seconds"
ps -Ao pid=,time=,comm= >"$tmp/after"
printf 'core%%\tmachine%%\tpid\tcommand  (%ss window, %s cores)\n' "$seconds" "$(ncpu)"
diff_snapshots "$tmp/before" "$tmp/after" "$seconds"
