#!/bin/bash
# Install the lint/check toolchain on Linux: GitHub Actions CI and the cloud
# session setup both call this. Versions live in mise.toml, not here; this
# script only gets mise, runs it, and puts the tools on PATH. On a workstation
# mkworld.sh runs `mise install` instead and mise's shims do the PATH part.
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# renovate: datasource=github-releases depName=jdx/mise
MISE_VERSION="${MISE_VERSION:-2026.10.6}"

case "$(uname -m)" in
  x86_64)        MISE_ARCH=x64 ;;
  aarch64|arm64) MISE_ARCH=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Run a command as root, using sudo only when we are not already root.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# zsh (zsh-syntax) + shellcheck (shell-lint) + bats (unit tests) + luajit
# (lua-syntax: parse nvim's Lua with its own runtime) + jq (unit tests:
# install_claude_tmux_hooks.sh and its bats suite) via apt. Unpinned: these
# follow the distro, as they always have.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get update -qq || true
  as_root apt-get install -y -qq zsh shellcheck bats luajit jq >/dev/null
fi

# A pinned release binary rather than mise.run's installer script, which would
# install whatever is newest on the day.
if ! command -v mise >/dev/null 2>&1; then
  tmp="$(mktemp)"
  curl -sSfL -o "$tmp" \
    "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${MISE_ARCH}"
  as_root install -m 0755 "$tmp" /usr/local/bin/mise
  rm -f "$tmp"
fi

cd "$BASE_DIR"
# A fresh container has never trusted this checkout, and mise refuses an
# untrusted config rather than prompting when there is no terminal.
export MISE_TRUSTED_CONFIG_PATHS="$BASE_DIR/mise.toml"
mise install

# Links into /usr/local/bin rather than mise's shims: a shim picks the version
# from the current directory, and the bats suites run these tools from temp
# directories outside the repo. Every executable of every tool in mise.toml, so
# adding a tool there needs no edit here. -f so a version bump replaces an
# older link.
mise ls --local --json | jq -r 'keys[]' | while read -r tool; do
  mise bin-paths "$tool" | while read -r dir; do
    for f in "$dir"/*; do
      if [ -f "$f" ] && [ -x "$f" ]; then
        as_root ln -sf "$f" "/usr/local/bin/${f##*/}"
      fi
    done
  done
done
