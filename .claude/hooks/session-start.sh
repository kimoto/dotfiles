#!/bin/bash
# Claude Code on the web — SessionStart hook.
#
# Installs this dotfiles repo's dev/CI tooling into the ephemeral web sandbox so
# the lefthook checks and bin/ lint scripts behave the same as in GitHub Actions.
# Without this, every fresh web session is missing zsh, yq, gitleaks, ratchet,
# shellcheck and lefthook, so commits get blocked and the lint scripts fail.
#
# Local (non-remote) sessions are skipped — on a real machine `brew bundle` /
# bin/mkworld.sh already set everything up.
set -euo pipefail

# Only run inside the remote web sandbox.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Versions pinned to match .github/workflows/ci.yml.
GITLEAKS_VERSION=8.30.1
RATCHET_VERSION=0.11.4
YQ_VERSION=4.53.2
LEFTHOOK_VERSION=2.1.9

SUDO=""
[ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

log() { echo "[session-start] $*"; }

# 1. apt packages: zsh (syntax check), shellcheck, fzf.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y -qq zsh shellcheck fzf >/dev/null
fi

# 2. mikefarah yq — config-syntax check relies on `yq -p toml|json|yaml`.
if ! { command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi mikefarah; }; then
  $SUDO curl -sSfL -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"
  $SUDO chmod +x /usr/local/bin/yq
fi

# 3. gitleaks — secret scanning (pre-commit + pre-push).
if ! command -v gitleaks >/dev/null 2>&1; then
  curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | $SUDO tar -xz -C /usr/local/bin gitleaks
fi

# 4. ratchet — GitHub Actions pinning check.
if ! command -v ratchet >/dev/null 2>&1; then
  curl -sSfL "https://github.com/sethvargo/ratchet/releases/download/v${RATCHET_VERSION}/ratchet_${RATCHET_VERSION}_linux_amd64.tar.gz" \
    | $SUDO tar -xz -C /usr/local/bin ratchet
fi

# 5. lefthook + install the git hooks so commits run the same checks as CI.
if ! command -v lefthook >/dev/null 2>&1; then
  curl -sSfL "https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION}_Linux_x86_64.gz" \
    | gunzip > /tmp/lefthook
  $SUDO install -m 0755 /tmp/lefthook /usr/local/bin/lefthook
  rm -f /tmp/lefthook
fi
if cd "${CLAUDE_PROJECT_DIR:-$PWD}"; then
  lefthook install >/dev/null 2>&1 || true
fi

log "tooling ready: zsh shellcheck fzf yq gitleaks ratchet lefthook"
