#!/bin/bash

# When was each alias and function the zsh config defines last typed?
#
# A pruning aid: a helper nobody has typed for months is a candidate to drop.
# The history already holds the answer, so this records nothing new:
# extended_history stamps every entry, and histignorealldups keeps only an
# entry's latest use — the count is lost, the last-used date survives.
#
# Left out, because they are never typed: names starting with `_`, zle widgets
# (reached by a key), zsh hook functions, and helpers the config calls itself
# at startup. Abbreviations are left out too: the history keeps what they
# expand to, so `di` and a typed `git diff` look the same.
#
# Usage: usage_report.sh [--days N | --all]
#   --days N  names last typed N or more days ago, or never (default 90)
#   --all     every name with its last use
# Output: <YYYY-MM-DD|never>\t<alias|function>\t<name>, oldest first, after a
# line saying how far back the history goes — "never" means nothing before
# that date.
#
# Env: HISTFILE (default ~/.zsh_history); USAGE_REPORT_NOW (epoch, tests);
# USAGE_REPORT_CONFIG (space-separated config files, tests).

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
HISTORY="${HISTFILE:-$HOME/.zsh_history}"
read -r -a CONFIG <<<"${USAGE_REPORT_CONFIG:-$BASE_DIR/.zshrc $BASE_DIR/config/zsh/abbr.zsh}"
NOW="${USAGE_REPORT_NOW:-$(date +%s)}"

days=90
case "${1:-}" in
    --all) days=-1 ;;
    --days) days="${2:?usage: usage_report.sh [--days N | --all]}" ;;
    "") ;;
    *) echo "usage: usage_report.sh [--days N | --all]" >&2; exit 2 ;;
esac

if [ ! -r "$HISTORY" ]; then
    echo "usage_report: cannot read history: $HISTORY" >&2
    exit 1
fi

# The histfile is metafied zsh bytes, not UTF-8; C keeps awk from choking.
export LC_ALL=C

# macOS awk has no strftime, so dates are worked out from the epoch by hand.
# They are UTC days: a use just after local midnight can land on the day before.
awk -v now="$NOW" -v days="$days" '
    function ymd(ts,   z, era, doe, yoe, y, doy, mp, d, m) {
        z = int(ts / 86400) + 719468
        era = int(z / 146097); doe = z - era * 146097
        yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
        y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
        mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1
        m = mp < 10 ? mp + 3 : mp - 9
        return sprintf("%04d-%02d-%02d", y + (m <= 2), m, d)
    }

    FNR == 1 { file++ }

    # Config files: collect definitions and the names that are never typed.
    file < ncfg {
        line = $0
        sub(/^[ \t]+/, "", line)
        if (line ~ /^#/) next
        if (match(line, /^alias [A-Za-z0-9_.-]+=/)) {
            name = substr(line, 7, RLENGTH - 7); kind[name] = "alias"; next
        }
        if (match(line, /^function [A-Za-z0-9_.-]+/)) {
            name = substr(line, 10, RLENGTH - 9); kind[name] = "function"; next
        }
        if (match(line, /^[A-Za-z0-9_.-]+ *\(\)/)) {
            name = substr(line, 1, RLENGTH); sub(/ *\(\)$/, "", name)
            kind[name] = "function"; next
        }
        n = split(line, w, /[ \t]+/)
        if (w[1] == "zle" && w[2] == "-N") skip[w[3]] = 1
        else if (w[1] == "add-zsh-hook") skip[w[3]] = 1
        else if (w[1] == "zstyle") skip[w[n]] = 1
        else if ($0 ~ /^[A-Za-z0-9_.-]+([ \t]|$)/) startup[w[1]] = 1
        next
    }

    # History: ": <start>:<elapsed>;<command>". A continuation line of a
    # multi-line entry has no stamp and belongs to the entry above it.
    {
        if (match($0, /^: [0-9]+:[0-9]+;/)) {
            split(substr($0, 3), t, ":"); ts = t[1] + 0
            cmd = substr($0, RLENGTH + 1)
            if (oldest == "" || ts < oldest) oldest = ts
        } else cmd = $0
        if (ts == "") next
        # A command word starts the line or follows ; & | ( or a backtick.
        n = split(cmd, part, /[;&|(`]/)
        for (i = 1; i <= n; i++) {
            sub(/^[ \t]+/, "", part[i])
            split(part[i], w, /[ \t]+/)
            word = (w[1] == "sudo" || w[1] == "noglob" || w[1] == "nocorrect") ? w[2] : w[1]
            if (word != "" && (!(word in last) || ts > last[word])) last[word] = ts
        }
    }

    END {
        if (oldest == "") { print "usage_report: no stamped entries (is extended_history on?)" > "/dev/stderr"; exit 1 }
        print "# history since " ymd(oldest)
        for (name in kind) {
            if (name ~ /^(_|TRAP)/ || name in skip || name in startup) continue
            if (name ~ /^(chpwd|precmd|preexec|periodic|zshaddhistory|zshexit)$/) continue
            if (name in last) {
                if (days >= 0 && now - last[name] < days * 86400) continue
                print ymd(last[name]) "\t" kind[name] "\t" name
            } else print "never\t" kind[name] "\t" name
        }
    }
' ncfg="$((${#CONFIG[@]} + 1))" "${CONFIG[@]}" "$HISTORY" | sort -t "$(printf '\t')" -k1,1 -k3,3
