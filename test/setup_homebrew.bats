#!/usr/bin/env bats

# Behavioural tests for which Brewfiles bin/setup_homebrew.sh installs.
#
# Brewfile.common is the expensive half of a bootstrap, and CI wants the cheap
# one. That choice used to be made by sniffing $CI, which meant the *one* job
# built to run the bootstrap with nothing skipped could not opt back in: GitHub
# Actions exports CI=true into every step, so the full-bootstrap job installed
# Brewfile.basic and then failed its own "every Brewfile is satisfied" check.
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
  for f in basic common macos linux; do : >"$REPO/Brewfile.$f"; done

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

@test "by default both Brewfile.basic and Brewfile.common are installed" {
  run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"Brewfile.basic"* ]]
  [[ "$(bundles)" == *"Brewfile.common"* ]]
}

@test "SKIP_BREWFILE_COMMON=1 drops the expensive bundle and keeps the rest" {
  SKIP_BREWFILE_COMMON=1 run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"Brewfile.basic"* ]]
  [[ "$(bundles)" != *"Brewfile.common"* ]]
}

@test "the platform bundle is installed either way" {
  case "$(uname)" in
    Darwin) want="Brewfile.macos" ;;
    Linux) want="Brewfile.linux" ;;
    *) skip "no platform bundle on $(uname)" ;;
  esac
  SKIP_BREWFILE_COMMON=1 run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"$want"* ]]
}

@test "CI=true alone skips nothing: a CI job must ask for it" {
  CI=true run "$REPO/bin/setup_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$(bundles)" == *"Brewfile.common"* ]]
}
