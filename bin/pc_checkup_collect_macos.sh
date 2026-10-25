#!/bin/bash

# Print what this Mac starts on its own, what it exposes to the network, and
# its security settings, one `kind<TAB>key<TAB>detail` line each, sorted.
# The macOS half of windows/pc_checkup_collect.ps1: same kinds, same rules.
# bin/pc_checkup_diff.sh compares the output to a list of what is allowed; the
# pc-checkup skill decides what to do with the rest. Read-only: changes nothing.
#
# Keys carry only what should stay stable between runs (no PIDs), so a diff
# shows real change instead of noise. Detail is for the reader, never compared.
#
# Runs without sudo. A check that needs it prints `unknown` instead of failing,
# so a missing value shows up as a diff rather than as silence.

set -uo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
    echo "pc_checkup_collect_macos.sh: macOS only" >&2
    exit 2
fi

uid=$(id -u)
out=$(mktemp)
trap 'rm -f "$out"' EXIT

line() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$out"; }

# --- login: launchd jobs from third parties, unless disabled ---

disabled_gui=$(launchctl print-disabled "gui/$uid" 2>/dev/null || true)
disabled_sys=$(launchctl print-disabled system 2>/dev/null || true)

for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    [ -d "$dir" ] || continue
    case "$dir" in
        */LaunchDaemons) disabled=$disabled_sys ;;
        *) disabled=$disabled_gui ;;
    esac
    for plist in "$dir"/*.plist; do
        [ -e "$plist" ] || continue
        label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null || basename "$plist" .plist)
        if printf '%s\n' "$disabled" | grep -qF "\"$label\" => disabled"; then
            continue
        fi
        prog=$(/usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)
        line login "launchd:$label" "$prog"
    done
done

# Login Items from System Settings. Asking System Events needs Automation
# permission for the calling terminal; without it this prints nothing extra.
items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)
if [ -n "$items" ]; then
    printf '%s\n' "$items" | tr ',' '\n' | sed 's/^ *//' | while IFS= read -r name; do
        [ -n "$name" ] && line login "loginitem:$name"
    done
fi

# --- listen: TCP ports reachable from other machines ---

lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $1 "\t" $9 }' \
    | while IFS=$'\t' read -r cmd addr; do
        host=${addr%:*}
        port=${addr##*:}
        case "$host" in 127.*|'[::1]'|localhost) continue ;; esac
        # 49152+ is the dynamic range: a new one each start.
        [ "$port" -ge 49152 ] 2>/dev/null && port=dynamic
        line listen "$cmd:$port" "$host"
    done

# --- setting: one line per setting, the value inside the key ---

setting() { line setting "$1=$2"; }

case "$(fdesetup status 2>/dev/null)" in
    *"FileVault is On"*) setting filevault on ;;
    *"FileVault is Off"*) setting filevault off ;;
    *) setting filevault unknown ;;
esac

fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
case "$fw" in
    *enabled*) setting firewall on ;;
    *disabled*) setting firewall off ;;
    *) setting firewall unknown ;;
esac

case "$(spctl --status 2>/dev/null)" in
    *"assessments enabled"*) setting gatekeeper on ;;
    *"assessments disabled"*) setting gatekeeper off ;;
    *) setting gatekeeper unknown ;;
esac

case "$(csrutil status 2>/dev/null)" in
    *"enabled."*) setting sip on ;;
    *"disabled."*) setting sip off ;;
    *) setting sip unknown ;;
esac

su_plist=/Library/Preferences/com.apple.SoftwareUpdate
case "$(defaults read "$su_plist" CriticalUpdateInstall 2>/dev/null)" in
    1) setting security-updates-auto on ;;
    0) setting security-updates-auto off ;;
    *) setting security-updates-auto unknown ;;
esac

# Remote Login (sshd) shows up as an enabled com.openssh.sshd.
if printf '%s\n' "$disabled_sys" | grep -qF '"com.openssh.sshd" => enabled'; then
    setting remote-login on
else
    setting remote-login off
fi

# One line per kind+key: a port open on both IPv4 and IPv6 is one finding.
sort "$out" | awk -F'\t' '
    { id = $1 "\t" $2 }
    id == prev { if ($3 != "" && index(", " d ", ", ", " $3 ", ") == 0) d = d (d == "" ? "" : ", ") $3; next }
    NR > 1 { print prev "\t" d }
    { prev = id; d = $3 }
    END { if (NR) print prev "\t" d }
'
