#!/usr/bin/env bats

# Behavioural tests for bin/brew_bundle_check.sh, the shell-startup reminder that
# nags when a Brewfile bundle has uninstalled packages.
#
# The script shells out to `brew bundle check`, so each test runs a *copy* of it
# inside a throwaway repo with Brewfiles present and a stub `brew` on PATH whose
# exit code is scripted via BREW_CHECK_RC ("0" = satisfied, anything else =
# missing). XDG_CACHE_HOME is redirected into the temp dir so the 24h throttle
# stamp and the cached result file can be inspected and pre-seeded. Warnings go
# to stderr, which bats folds into $output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export XDG_CACHE_HOME="$TMP/cache"

  REPO="$TMP/repo"
  mkdir -p "$REPO/bin"
  cp "$REPO_ROOT/bin/brew_bundle_check.sh" "$REPO/bin/brew_bundle_check.sh"
  chmod +x "$REPO/bin/brew_bundle_check.sh"
  SCRIPT="$REPO/bin/brew_bundle_check.sh"
  # The script checks these by name; their contents are irrelevant to the stub.
  for f in Brewfile.basic Brewfile.common Brewfile.macos Brewfile.linux; do
    echo "brew \"placeholder\"" >"$REPO/$f"
  done

  # Stub brew: `brew bundle check ...` exits with BREW_CHECK_RC (default 0).
  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
if [ "$1" = "bundle" ] && [ "$2" = "check" ]; then
  exit "${BREW_CHECK_RC:-0}"
fi
exit 0
STUBEOF
  chmod +x "$STUB/brew"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "DOTFILES_NO_BREW_CHECK short-circuits with no output" {
  BREW_CHECK_RC=1 DOTFILES_NO_BREW_CHECK=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when brew is not installed" {
  # Run with a PATH that has neither the stub nor a real brew.
  PATH="/nonexistent" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when all bundles are satisfied" {
  BREW_CHECK_RC=0 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # The result cache exists but is empty.
  [ -f "$XDG_CACHE_HOME/dotfiles/brew_missing" ]
  [ ! -s "$XDG_CACHE_HOME/dotfiles/brew_missing" ]
}

@test "warns and names the unsatisfied bundle when packages are missing" {
  BREW_CHECK_RC=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[brew]"* ]]
  [[ "$output" == *"Brewfile.basic"* ]]
  [[ "$output" == *"brew bundle install --file="* ]]
}

@test "caches the result and a stamp, then reuses it without re-checking" {
  BREW_CHECK_RC=1 run "$SCRIPT"
  [ -f "$XDG_CACHE_HOME/dotfiles/last_brew_check" ]
  [ -s "$XDG_CACHE_HOME/dotfiles/brew_missing" ]

  # Within 24h the stub flipping to "satisfied" must NOT change the cached nag.
  BREW_CHECK_RC=0 run "$SCRIPT"
  [[ "$output" == *"Brewfile.basic"* ]]
}

@test "re-checks once the throttle stamp is older than 24h" {
  BREW_CHECK_RC=1 run "$SCRIPT"          # seed a "missing" cache
  [[ "$output" == *"Brewfile.basic"* ]]

  # Backdate the stamp beyond 24h; a now-satisfied check must clear the nag.
  echo "$(( $(date +%s) - 90000 ))" >"$XDG_CACHE_HOME/dotfiles/last_brew_check"
  BREW_CHECK_RC=0 run "$SCRIPT"
  [ -z "$output" ]
}
