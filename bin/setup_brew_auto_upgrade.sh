#!/bin/bash

# Installs the launchd agent that runs brew_auto_upgrade.sh every day, and takes
# out the homebrew/autoupdate agent it replaces. Idempotent: a rerun with the
# agent already current changes nothing. launchd is macOS-only, so this is a
# no-op elsewhere.
#
# StartCalendarInterval, not StartInterval: an interval timer restarts at every
# login, so on a machine rebooted more often than the interval it never fires.
# A calendar slot missed while asleep runs once on wake.

set -eu

LABEL=local.dotfiles.brew-auto-upgrade
# Replaced agents: the pre-adoption domt4 tap's, and the official tap's.
OLD_LABELS=(com.github.domt4.homebrew-autoupdate com.github.homebrew.homebrew-autoupdate)

if [ "$(uname)" != "Darwin" ]; then
    echo "the brew auto-upgrade agent relies on launchd; skipping on non-macOS." >&2
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
    echo "brew not found; skipping auto-upgrade setup." >&2
    exit 0
fi

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
agents_dir="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs/dotfiles"
plist="$agents_dir/$LABEL.plist"
domain="gui/$(id -u)"

for old in "${OLD_LABELS[@]}"; do
    if [ -e "$agents_dir/$old.plist" ]; then
        launchctl bootout "$domain/$old" >/dev/null 2>&1 || true
        rm -f "$agents_dir/$old.plist"
        echo "removed the $old agent"
    fi
done
# Untrusted since Homebrew adopted the command, and nothing uses it any more.
if "$BREW_BIN" tap 2>/dev/null | grep -qx 'domt4/autoupdate'; then
    "$BREW_BIN" untap domt4/autoupdate >/dev/null 2>&1 || true
fi

mkdir -p "$agents_dir" "$log_dir"
tmp=$(mktemp "$agents_dir/.$LABEL.XXXXXX")
trap 'rm -f "$tmp"' EXIT
# 12:00, when the machine is most likely awake; a missed slot runs on wake.
cat >|"$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO_DIR/bin/brew_auto_upgrade.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(dirname "$BREW_BIN"):/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>12</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_dir/brew_auto_upgrade.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/brew_auto_upgrade.log</string>
</dict>
</plist>
EOF

if cmp -s "$tmp" "$plist" && launchctl print "$domain/$LABEL" >/dev/null 2>&1; then
    echo "brew auto-upgrade agent already installed; nothing to do."
    exit 0
fi

mv -f "$tmp" "$plist"
launchctl bootout "$domain/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$plist"
# Run once now, so the first stamp (and any first failure) shows up today
# rather than at the next noon.
launchctl kickstart "$domain/$LABEL"
echo "brew auto-upgrade agent installed: daily at 12:00, log in $log_dir/brew_auto_upgrade.log"
