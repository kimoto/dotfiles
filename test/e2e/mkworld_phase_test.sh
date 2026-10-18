#!/bin/bash
# mkworld.sh on a machine that cannot climb past <phase> must stop there, say
# so, and exit 0 — not abort at the first install it cannot do.
#
#   test/e2e/mkworld_phase_test.sh minimal   # zsh hidden from PATH
#   test/e2e/mkworld_phase_test.sh basic     # zsh present, Homebrew not installable
#
# Each run gets its own empty $HOME, the way a fresh account would.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

want="${1:-}"
case "$want" in
  minimal|basic) ;;
  *) die "usage: $0 minimal|basic" ;;
esac

if [ "$want" = basic ]; then
  # mkworld.sh looks for Homebrew at these fixed prefixes, so an empty $HOME and
  # PATH cannot hide one that is already installed: the climb would go past
  # basic and read as a mkworld bug.
  for prefix in /opt/homebrew /home/linuxbrew/.linuxbrew; do
    [ -x "$prefix/bin/brew" ] && die "Homebrew is already at $prefix; basic can only be tested where it is not"
  done
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/home"

# Without the caller's mise shims: the fresh $HOME has none of the tools they
# stand for, so mkworld's `mise install` would run a shim (rustup) that is mise
# again, waiting on that same install forever.
search_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/mise/shims/*$' | paste -sd: -)"
if [ "$want" = minimal ]; then
  # A PATH that is the real one minus zsh, so the rest of the OS stays as is.
  mkdir "$WORK/bin"
  IFS=: read -ra dirs <<<"$search_path"
  for d in "${dirs[@]}"; do
    for f in "$d"/*; do
      # An empty or missing PATH entry leaves the glob as a literal "*".
      [ -e "$f" ] || continue
      b="${f##*/}"
      [ "$b" = zsh ] && continue
      [ -e "$WORK/bin/$b" ] || ln -s "$f" "$WORK/bin/$b"
    done
  done
  search_path="$WORK/bin"
fi

# The proxy and CA settings pass through so this also runs behind a proxy.
keep=(HOME="$WORK/home" PATH="$search_path" LANG=C.UTF-8 MKWORLD_EXPECT="$want")
for v in HTTPS_PROXY https_proxy SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO; do
  [ -n "${!v:-}" ] && keep+=("$v=${!v}")
done

set +e
env -i "${keep[@]}" "$REPO/bin/mkworld.sh" </dev/null >"$WORK/log" 2>&1
rc=$?
set -e
grep -v '^+' "$WORK/log"
[ "$rc" = 0 ] || die "mkworld.sh exited $rc"

last="$(tail -n 1 "$WORK/log")"
case "$last" in
  "mkworld: reached $want "*|"mkworld: reached $want") ;;
  *) die "expected to stop at $want, got: $last" ;;
esac
[ -L "$WORK/home/.bashrc" ] || die "mklink.sh did not link ~/.bashrc"
echo PASS
