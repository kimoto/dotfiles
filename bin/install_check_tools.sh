#!/bin/bash
# Install the lint/check toolchain on Linux: GitHub Actions CI and the cloud
# session setup both call this. Versions live in mise.toml, not here; this
# script only gets mise, runs it, and puts the tools on PATH. On a workstation
# mkworld.sh runs `mise install` instead and mise's shims do the PATH part.
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# The same mise a workstation runs `mise lock` with: releases write the pipx:
# entries of mise.lock differently, and `--locked` below rejects another's.
# renovate: datasource=github-releases depName=jdx/mise
MISE_VERSION="${MISE_VERSION:-2026.10.13}"

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

# zsh (zsh-syntax) + bats (unit tests) + luajit
# (lua-syntax: parse nvim's Lua with its own runtime) + jq (unit tests:
# install_claude_tmux_hooks.sh and its bats suite) + gpg (checks mise's
# signature below) via apt. Unpinned: these follow the distro, as they always
# have.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  as_root apt-get update -qq || true
  # The cloud image ships its own /etc/zsh/zshrc without the zsh package, so
  # dpkg stops at a conffile prompt; with no terminal that aborts the install.
  # Keep the file already there: it belongs to the image, not to us.
  # CHECK_TOOLS_APT_ARCHIVES lets CI keep the .debs in a directory it caches:
  # the runners' mirror sometimes serves them at ~60 kB/s, which turns a 10 s
  # step into two minutes. apt still resolves against today's lists, so a stale
  # cache only means downloading what changed.
  apt_cache=()
  if [ -n "${CHECK_TOOLS_APT_ARCHIVES:-}" ]; then
    as_root mkdir -p "$CHECK_TOOLS_APT_ARCHIVES/partial"
    apt_cache=(-o "Dir::Cache::Archives=$CHECK_TOOLS_APT_ARCHIVES")
  fi
  as_root apt-get install -y -qq ${apt_cache[@]+"${apt_cache[@]}"} \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    zsh bats luajit jq gpg >/dev/null
fi

# A pinned release binary rather than mise.run's installer script, which would
# install whatever is newest on the day. A version names no bytes, so the binary
# must also match the SHASUMS256 list mise's release key signed: mise is what
# checks every other tool against mise.lock, so a swapped mise would make that
# check meaningless. A signature rather than a sha256 written here keeps
# Renovate able to bump MISE_VERSION alone.
# The key is the one https://mise.jdx.dev/gpg-key.pub serves; it expires
# 2028-01-02, after which a new one from there replaces both values.
MISE_RELEASE_KEY="${MISE_RELEASE_KEY:-$BASE_DIR/bin/keys/mise-release.asc}"
MISE_RELEASE_FPR="${MISE_RELEASE_FPR:-24853EC9F655CE80B48E6C3A8B81C9D17413A06D}"
# Overridable only so the bats suite can install somewhere it may write.
MISE_INSTALL_DIR="${MISE_INSTALL_DIR:-/usr/local/bin}"

# Prints the sha256 list in $1 (a clearsigned SHASUMS256.asc) if, and only if,
# the pinned key made a good signature over it.
verified_sums() {
  local gnupghome status
  gnupghome="$(mktemp -d)"
  GNUPGHOME="$gnupghome" gpg --batch --quiet --import "$MISE_RELEASE_KEY" 2>/dev/null
  status="$(GNUPGHOME="$gnupghome" gpg --batch --status-fd 1 --output - --decrypt "$1" 2>/dev/null)"
  rm -rf "$gnupghome"
  # VALIDSIG's last field is the primary key's fingerprint, which is what
  # MISE_RELEASE_FPR names; GOODSIG alone would accept any key in the file.
  grep -qE "^\[GNUPG:\] VALIDSIG .* ${MISE_RELEASE_FPR}\$" <<<"$status" || return 1
  grep -v '^\[GNUPG:\]' <<<"$status"
}

if ! command -v mise >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  asset="mise-v${MISE_VERSION}-linux-${MISE_ARCH}"
  release="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}"
  curl -sSfL -o "$tmp/$asset" "$release/$asset"
  curl -sSfL -o "$tmp/SHASUMS256.asc" "$release/SHASUMS256.asc"
  sums="$(verified_sums "$tmp/SHASUMS256.asc")" || {
    echo "mise $MISE_VERSION: SHASUMS256.asc is not signed by $MISE_RELEASE_FPR" >&2
    exit 1
  }
  want="$(awk -v f="./$asset" '$2 == f { print $1 }' <<<"$sums")"
  got="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    echo "mise $MISE_VERSION: $asset does not match its signed sha256" >&2
    exit 1
  fi
  as_root install -m 0755 "$tmp/$asset" "$MISE_INSTALL_DIR/mise"
  rm -rf "$tmp"
fi

cd "$BASE_DIR"
# A fresh container has never trusted this checkout, and mise refuses an
# untrusted config rather than prompting when there is no terminal.
export MISE_TRUSTED_CONFIG_PATHS="$BASE_DIR/mise.toml"
# A tool that fails to install must not cost the ones that did: a shared egress
# IP can spend api.github.com's unauthenticated quota before we arrive, and an
# early exit here would leave every tool off PATH, installed or not.
# --locked downloads from the URL and checks the sha256 in mise.lock, with no
# GitHub API call: on a shared egress IP the unauthenticated API quota is often
# already spent. A version bumped in mise.toml without `mise lock` fails here.
# Only this repo's tools (--local) are installed and linked: a global mise
# config (CI links config/ into ~/.config) asks for unpinned tools the lockfile
# cannot hold, and they are not ours to put on PATH.
# A read loop rather than mapfile: macOS's /bin/bash is 3.2, which has no
# mapfile, and the bats suite for this script runs there from lefthook.
tools=()
while IFS= read -r tool; do
  tools+=("$tool")
done < <(mise ls --local --json | jq -r 'keys[]')
failed=0
mise install --locked "${tools[@]}" || failed=1

# Links into /usr/local/bin rather than mise's shims: a shim picks the version
# from the current directory, and the bats suites run these tools from temp
# directories outside the repo. -f so a version bump replaces an older link.
# Every executable in each tool's bin dir is linked under its own name, so
# mise.toml stays the only list of tools; that also links a few harmless
# extras (an arch-suffixed copy of a binary, uv's uvx).
# CHECK_TOOLS_BIN_DIR exists for the tests, which cannot write /usr/local/bin.
bin_dir="${CHECK_TOOLS_BIN_DIR:-/usr/local/bin}"
for tool in "${tools[@]}"; do
  # A tool the install above skipped may have no bin path to report; it is
  # already counted in $failed.
  { mise bin-paths "$tool" 2>/dev/null || true; } | while read -r dir; do
    for exe in "$dir"/*; do
      if [ -f "$exe" ] && [ -x "$exe" ]; then
        as_root ln -sf "$exe" "$bin_dir/${exe##*/}"
      fi
    done
  done
done
exit "$failed"
