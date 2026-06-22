#!/bin/bash
# Single source of truth for the lint/check toolchain (pinned versions + install).
# Shared by GitHub Actions CI and the Claude Code web SessionStart hook so the
# versions live in exactly ONE place. Targets Linux (apt + GitHub release
# binaries); on a real machine use `brew bundle` (Brewfile.*) instead.
set -euo pipefail

# The one place to bump versions (override via env if needed).
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
RATCHET_VERSION="${RATCHET_VERSION:-0.11.4}"
YQ_VERSION="${YQ_VERSION:-4.53.2}"
BIOME_VERSION="${BIOME_VERSION:-2.5.0}"

# Run a command as root, using sudo only when we are not already root.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# zsh (zsh-syntax check) + shellcheck (shell-lint) via apt.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get update -qq || true
  as_root apt-get install -y -qq zsh shellcheck >/dev/null
fi

# mikefarah yq (config-syntax: `yq -p toml|json|yaml`).
if ! { command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi mikefarah; }; then
  as_root curl -sSfL -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"
  as_root chmod +x /usr/local/bin/yq
fi

# gitleaks (secret scanning).
if ! command -v gitleaks >/dev/null 2>&1; then
  curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | as_root tar -xz -C /usr/local/bin gitleaks
fi

# ratchet (GitHub Actions pinning check).
if ! command -v ratchet >/dev/null 2>&1; then
  curl -sSfL "https://github.com/sethvargo/ratchet/releases/download/v${RATCHET_VERSION}/ratchet_${RATCHET_VERSION}_linux_amd64.tar.gz" \
    | as_root tar -xz -C /usr/local/bin ratchet
fi

# biome (config-syntax: validates .jsonc, e.g. config/fastfetch/config.jsonc).
if ! command -v biome >/dev/null 2>&1; then
  as_root curl -sSfL -o /usr/local/bin/biome \
    "https://github.com/biomejs/biome/releases/download/@biomejs/biome@${BIOME_VERSION}/biome-linux-x64"
  as_root chmod +x /usr/local/bin/biome
fi
