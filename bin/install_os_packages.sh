#!/bin/bash
# Install through apt the OS packages the bootstrap needs and a fresh Ubuntu
# leaves out, so README's one command gets past them. Only what is missing, and
# only where apt and root (directly or through sudo) are at hand; anywhere else
# it does nothing, and the step that needs a package names it.

set -euo pipefail

# Each one, and the step that stops without it:
#   git         README's clone (README installs it itself; listed for a rerun)
#   zsh         the basic phase
#   curl        setup_homebrew.sh, to fetch the Homebrew installer
#   libatomic1  mise, whose Linux node links it
PACKAGES=(git zsh curl libatomic1)

if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-query >/dev/null 2>&1; then
    exit 0
fi

missing=()
for pkg in "${PACKAGES[@]}"; do
    # The status, not `command -v`: libatomic1 has no command, and a test that
    # hides zsh from PATH must not set off an install.
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null || true)"
    [[ "$status" == ii* ]] || missing+=("$pkg")
done
[ "${#missing[@]}" -gt 0 ] || exit 0

# sudo resets the environment, so DEBIAN_FRONTEND goes on its command line.
if [ "$(id -u)" = 0 ]; then
    as_root() { DEBIAN_FRONTEND=noninteractive "$@"; }
elif command -v sudo >/dev/null 2>&1; then
    as_root() { sudo DEBIAN_FRONTEND=noninteractive "$@"; }
else
    echo "install_os_packages: no sudo; install these first: ${missing[*]}" >&2
    exit 0
fi

echo "install_os_packages: installing ${missing[*]}" >&2
as_root apt-get update
as_root apt-get install -y --no-install-recommends "${missing[@]}"
