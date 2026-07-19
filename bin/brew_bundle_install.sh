#!/bin/bash

# Interactive `brew bundle install` for every Brewfile this machine uses.
#
# Companion to brew_bundle_check.sh: that startup reminder only nags and points
# here; this script actually installs, and only when a human asks. It is never
# wired into shell startup, and it refuses to run without a terminal on both
# stdin and stdout, so CI, hooks, or an AI agent invoking it is a no-op.
#
# Flow: one y/N confirmation, then a fully unattended pass — sudo is disabled
# via a failing SUDO_ASKPASS so a cask that needs a password fails fast instead
# of blocking on a prompt, letting you walk away. Everything that needs a human
# is batched into a final interactive phase: trusting third-party taps,
# force-upgrading casks whose app self-updated out from under Homebrew, and
# re-running the failed bundles with sudo available.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd) || exit 1

usage() {
  cat <<'EOF'
Usage: brew_bundle_install.sh [--help]

Interactively install every Brewfile bundle for this machine
(Brewfile.basic, Brewfile.common, plus the platform Brewfile).

Phase 1 runs unattended after a single y/N confirmation; anything that
needs a human (sudo password, untrusted tap, cask overwritten by a
self-update) is collected and prompted for at the end.
EOF
}

# y/N prompt, default no.
confirm() {
  local reply
  printf '%s [y/N] ' "$1"
  IFS= read -r reply || return 1
  [[ "$reply" == [yY]* ]]
}

# "Error: Refusing to load cask X from untrusted tap T." -> T
parse_untrusted_taps() {
  sed -E -n 's/.*untrusted tap ([^ ]+)\.$/\1/p' "$1" | sort -u
}

# "Error: C: It seems there is already an App at '...'." -> C
# (the cask's app was moved or self-updated outside Homebrew)
parse_app_conflicts() {
  sed -E -n "s/^Error: ([^:]+): It seems there is already an App at.*/\1/p" "$1" | sort -u
}

# "Installing/Upgrading D has failed!" -> D
parse_failed_deps() {
  sed -E -n 's/^(Installing|Upgrading) (.+) has failed!$/\2/p' "$1" | sort -u
}

# Absolute path to an always-failing askpass helper. sudo exec()s this, so it
# must be a real file: `type -P` forces a PATH lookup, whereas `command -v`
# would return the bash builtin's bare name "false", which sudo cannot run —
# silently re-enabling tty password prompts mid-unattended-pass.
failing_askpass() {
  type -P false
}

# Sourced by test/brew_bundle_install.bats to unit-test the parsers.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  '') ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# Humans only: without a terminal, refuse before touching brew at all.
if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "brew_bundle_install.sh is interactive-only; run it from a terminal." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "brew not found; run bin/setup_homebrew.sh first." >&2
  exit 1
fi

# Same Brewfile selection as brew_bundle_check.sh.
files=(Brewfile.basic Brewfile.common)
case "$(uname)" in
  Darwin) files+=(Brewfile.macos) ;;
  Linux) files+=(Brewfile.linux) ;;
esac

echo "Brewfiles to install:"
for f in "${files[@]}"; do
  echo "  $f"
done
confirm "Install now? (unattended; steps needing a human run at the end)" || exit 0

log=$(mktemp -t brew_bundle_install) || exit 1
trap 'rm -f "$log"' EXIT

# A sudo askpass helper that always fails: any cask needing a password errors
# out immediately instead of prompting, and gets retried interactively below.
# Plain SUDO_ASKPASS (no HOMEBREW_ prefix) is what makes brew pass sudo -A.
askpass=$(failing_askpass)

failed_files=()
for f in "${files[@]}"; do
  [ -f "$REPO_DIR/$f" ] || continue
  echo
  echo "==> $f (unattended pass)"
  if ! SUDO_ASKPASS="$askpass" brew bundle install --file="$REPO_DIR/$f" </dev/null 2>&1 | tee -a "$log"; then
    failed_files+=("$f")
  fi
done

if [ "${#failed_files[@]}" -eq 0 ]; then
  echo
  echo "All bundles installed; nothing needed a human."
  exit 0
fi

echo
echo "==> Interactive phase: ${#failed_files[@]} bundle(s) had failures"
echo "Failed items:"
parse_failed_deps "$log" | sed 's/^/  - /'

# New Homebrew refuses casks from third-party taps until they are trusted.
while IFS= read -r tap; do
  [ -n "$tap" ] || continue
  if confirm "Trust tap $tap?"; then
    brew trust "$tap"
  fi
done < <(parse_untrusted_taps "$log")

# Casks whose app self-updated or was moved: overwrite it with brew's copy.
while IFS= read -r cask; do
  [ -n "$cask" ] || continue
  if confirm "Force-upgrade cask $cask? (overwrites the app in /Applications)"; then
    brew upgrade --cask --force "$cask"
  fi
done < <(parse_app_conflicts "$log")

# Catch-all: re-run the failed bundles with the terminal attached, so sudo
# password prompts (and anything else interactive) can now be answered.
status=0
for f in "${failed_files[@]}"; do
  echo
  if confirm "Re-run $f interactively? (sudo may prompt)"; then
    brew bundle install --file="$REPO_DIR/$f" || status=1
  fi
done

exit "$status"
