#!/bin/bash
# The commit author in an agent container, from setup_agent.sh and from the
# SessionStart refresh: set by a script rather than by each agent passing
# `-c user.*`, since an instruction can be forgotten and this cannot.
# Included, not linked: the container's ~/.gitconfig holds the platform's
# signing and proxy settings, which the workstation .gitconfig would replace.

set -uo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
source="$BASE_DIR/.gitconfig.agent"
global="$HOME/.gitconfig"

if [ -L "$global" ]; then
  echo "[cloud-setup] MISS git identity: $global is a symlink; left alone" >&2
  exit 1
fi
if ! git config --global --get-all include.path 2>/dev/null | grep -qxF "$source"; then
  git config --global --add include.path "$source" || true
fi
if [ "$(git config --global --includes user.email)" = "$(git config --file "$source" user.email)" ]; then
  echo "[cloud-setup] ok   git identity"
else
  echo "[cloud-setup] MISS git identity" >&2
  exit 1
fi
