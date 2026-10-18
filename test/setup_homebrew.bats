#!/usr/bin/env bats

# Behavioural tests for which Brewfiles bin/setup_homebrew.sh installs.
#
# Brewfile.extra is the expensive half of a bootstrap, and CI wants the cheap
# one. That choice used to be made by sniffing $CI, which meant the *one* job
# built to run the bootstrap with nothing skipped could not opt back in: GitHub
# Actions exports CI=true into every step, so the full-bootstrap job installed
# Brewfile.standard and then failed its own "every Brewfile is satisfied" check.
# Hence an explicit flag, and hence the last test here — $CI alone must not
# decide anything.
#
# Each test runs a *copy* of the script in a throwaway repo with empty Brewfiles
# and a stub `brew` on PATH that appends every `bundle install --file=X` to a
# log, so the assertions read which bundles were asked for, in order.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  TMP="$(cd "$TMP" && pwd -P)"

  REPO="$TMP/repo"
  mkdir -p "$REPO/bin"
  cp "$REPO_ROOT/bin/setup_homebrew.sh" "$REPO/bin/setup_homebrew.sh"
  chmod +x "$REPO/bin/setup_homebrew.sh"
  for f in standard extra macos linux; do : >"$REPO/Brewfile.$f"; done

  # Stub brew: records the bundle files it is handed. `command -v brew` has to
  # find it, or the script tries to install Homebrew over the network.
  STUB="$TMP/stub"
  mkdir -p "$STUB"
  BUNDLE_LOG="$TMP/bundles"
  : >"$BUNDLE_LOG"
  cat >"$STUB/brew" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in --file=*) echo "\${a#--file=}" >>"$BUNDLE_LOG" ;; esac
done
exit 0
EOF
  chmod +x "$STUB/brew"
  # BREW_BIN, not PATH: the script evals `brew shellenv` on a real machine,
  # which prepends the live prefix and would shadow a stub on PATH.
  export BREW_BIN="$STUB/brew"
}

teardown() {
  rm -rf "$TMP"
}

# The platform bundle is whichever of macos/linux this host is, and is not what
# these tests are about — assert on the two that are always in play.
bundles() { tr '\n' ' ' <"$BUNDLE_LOG"; }

@test "by default both Brewfile.standard and Brewfile.extra are installed" {
  run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"Brewfile.standard"* ]]
  [[ "$(bundles)" == *"Brewfile.extra"* ]]
}

@test "SKIP_BREWFILE_EXTRA=1 installs Brewfile.standard alone" {
  SKIP_BREWFILE_EXTRA=1 run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [ "$(bundles)" = "Brewfile.standard " ]
}

# The platform bundle (macOS casks, Linux stand-ins) belongs to the extra phase.
@test "the platform bundle comes with Brewfile.extra" {
  case "$(uname)" in
    Darwin) want="Brewfile.macos" ;;
    Linux) want="Brewfile.linux" ;;
    *) skip "no platform bundle on $(uname)" ;;
  esac
  run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"$want"* ]]
}

@test "CI=true alone skips nothing: a CI job must ask for it" {
  CI=true run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"Brewfile.extra"* ]]
}

# With no brew anywhere, the script fetches Homebrew's installer. A stub curl
# serves a fake one that leaves a marker and exits 3, so the run stops right
# after the installer instead of reaching for a real Homebrew.
fake_installer() {
  unset BREW_BIN
  NET="$TMP/net"
  mkdir -p "$NET"
  MARKER="$TMP/installer-ran"
  printf '#!/bin/bash\ntouch %q\nexit 3\n' "$MARKER" >"$TMP/install.sh"
  cat >"$NET/curl" <<EOF2
#!/bin/sh
while [ "\$#" -gt 0 ]; do
  [ "\$1" = -o ] && { cp "$TMP/install.sh" "\$2"; exit 0; }
  shift
done
exit 1
EOF2
  chmod +x "$NET/curl"
}

pin_hash() {
  sed -i.bak "s/^HOMEBREW_INSTALL_SHA256=.*/HOMEBREW_INSTALL_SHA256=\"$1\"/" "$REPO/bin/setup_homebrew.sh"
}

@test "runs the installer whose bytes match the pinned hash" {
  fake_installer
  if command -v sha256sum >/dev/null 2>&1; then
    pin_hash "$(sha256sum "$TMP/install.sh" | cut -d' ' -f1)"
  else
    pin_hash "$(shasum -a 256 "$TMP/install.sh" | cut -d' ' -f1)"
  fi
  PATH="$NET:/usr/bin:/bin" run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 3 ]
  [ -e "$MARKER" ]
}

@test "refuses an installer whose bytes do not match, without running it" {
  fake_installer
  pin_hash 0000000000000000000000000000000000000000000000000000000000000000
  PATH="$NET:/usr/bin:/bin" run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected 0000"* ]]
  [ ! -e "$MARKER" ]
}
