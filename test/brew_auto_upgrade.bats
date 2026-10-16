#!/usr/bin/env bats

# Behavioural tests for bin/brew_auto_upgrade.sh, the unattended daily job.
# A stub `brew` records its calls and answers `bundle list --formula` from
# STUB_FORMULAE; XDG_CACHE_HOME is a temp dir so the success stamp can be read.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  SCRIPT="$REPO_ROOT/bin/brew_auto_upgrade.sh"
  export XDG_CACHE_HOME="$TMP/cache"
  STAMP="$XDG_CACHE_HOME/dotfiles/brew_auto_upgrade_ok"
  CALLS="$TMP/calls.log"
  export CALLS
  : >"$CALLS"

  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  cat >"$STUB/brew" <<'STUBEOF'
#!/bin/bash
echo "brew $*" >>"$CALLS"
case "$1 $2" in
  "bundle list") printf '%s\n' ${STUB_FORMULAE:-} ;;
  "install --formula") exit "${STUB_INSTALL_RC:-0}" ;;
esac
exit 0
STUBEOF
  chmod +x "$STUB/brew"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "core_formulae drops tap-qualified names and duplicates" {
  # shellcheck source=/dev/null
  . "$SCRIPT"
  run core_formulae <<<$'jq\nowner/tap/thing\njq\ngit'
  [ "$output" = $'git\njq' ]
}

@test "installs only homebrew/core formulae, after brew update" {
  STUB_FORMULAE="jq owner/tap/thing" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -n '^brew update' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^brew install' "$CALLS" | cut -d: -f1)" ]
  grep -qx 'brew install --formula jq' "$CALLS"
  run grep -c 'owner/tap' "$CALLS"
  [ "$output" = 0 ]
  run grep -c -- '--cask' "$CALLS"
  [ "$output" = 0 ]
}

@test "stamps success, so the startup check can trust it" {
  STUB_FORMULAE="jq" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -s "$STAMP" ]
}

@test "a failed install leaves no stamp and exits non-zero" {
  STUB_FORMULAE="jq" STUB_INSTALL_RC=1 run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$STAMP" ]
}

@test "an empty formula list is a failure, not a quiet success" {
  STUB_FORMULAE="" run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$STAMP" ]
}
