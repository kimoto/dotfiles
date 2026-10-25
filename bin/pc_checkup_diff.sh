#!/bin/bash

# Compare a pc-checkup snapshot to the list of what this machine is allowed to
# run, expose and have set, and print only what needs a decision.
#
#   pc_checkup_diff.sh SNAPSHOT ALLOW
#
# SNAPSHOT is the output of bin/pc_checkup_collect_macos.sh or
# windows/pc_checkup_collect.ps1: `kind<TAB>key<TAB>detail`.
# ALLOW is `kind<TAB>key<TAB>reason`; blank lines and `#` lines are skipped.
# A key ending in `*` matches by prefix, for names that carry a version or an
# id that changes on update (`service:GoogleUpdaterService*`).
#
# Output, one per line:
#   new<TAB>kind<TAB>key<TAB>detail   in the snapshot, not allowed
#   gone<TAB>kind<TAB>key             allowed, not seen: prune or investigate
# Exit 0 when nothing is new, 1 when something is, 2 on usage error. `gone`
# alone does not fail: a removed app is not a risk.
#
# An allow entry with no reason is rejected (exit 2): the reason is what tells
# "still needed" from "nobody removed it" a year later.

set -euo pipefail

if [ "$#" -ne 2 ] || [ ! -r "$1" ] || [ ! -r "$2" ]; then
    echo "usage: $(basename "$0") SNAPSHOT ALLOW" >&2
    exit 2
fi

awk -F'\t' '
    FNR == NR {
        if ($0 ~ /^[[:space:]]*(#|$)/) next
        if (NF < 3 || $3 ~ /^[[:space:]]*$/) {
            printf "allow line %d has no reason: %s\n", FNR, $0 > "/dev/stderr"
            bad = 1
            next
        }
        id = $1 "\t" $2
        if (substr($2, length($2)) == "*") {
            prefix[$1 "\t" substr($2, 1, length($2) - 1)] = id
        } else {
            exact[id] = 1
        }
        seen[id] = 0
        next
    }
    {
        id = $1 "\t" $2
        if (id in exact) { seen[id] = 1; next }
        for (p in prefix) {
            if (index(id, p) == 1) { seen[prefix[p]] = 1; matched = 1 }
        }
        if (matched) { matched = 0; next }
        print "new\t" $0
        found = 1
    }
    END {
        if (bad) exit 2
        for (id in seen) if (!seen[id]) gone[++n] = id
        # Sorted so two runs on the same input print the same thing.
        for (i = 2; i <= n; i++) {
            v = gone[i]
            for (j = i - 1; j >= 1 && gone[j] > v; j--) gone[j + 1] = gone[j]
            gone[j + 1] = v
        }
        for (i = 1; i <= n; i++) print "gone\t" gone[i]
        exit found ? 1 : 0
    }
' "$2" "$1"
