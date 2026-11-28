#!/usr/bin/env bats

# Tests for bin/claude_settings_lib.sh as all six bin/install_claude_*.sh use
# it together: hooks that share an event and a matcher sit in one group, and
# one installer's rerun or uninstall touches only its own hooks, even inside a
# group it shares. Each test runs against a throwaway $HOME.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.claude/settings.json"
  # Full file names, so bin/run_tests.sh picks this file when any of them changes.
  INSTALLERS="install_claude_tmux_hooks.sh install_claude_idle_hooks.sh
    install_claude_context_hooks.sh install_claude_secret_scan_hook.sh
    install_claude_review_gate.sh install_claude_pr_hooks.sh"
  # guarded() writes a different command when this is set.
  unset CLAUDE_HOOK_BIN
}

teardown() {
  rm -rf "$TMP"
}

install_all() {
  for i in $INSTALLERS; do
    "$REPO_ROOT/bin/$i" 2>/dev/null
  done
}

hook_count() {
  jq '[.hooks[][].hooks[]] | length' "$SETTINGS"
}

@test "hooks that share an event and a matcher sit in one group" {
  install_all
  dupes="$(jq -r '.hooks | to_entries[] | .key as $e
    | [.value[] | .matcher // ""] | group_by(.)[] | select(length > 1)
    | "\($e) \(.[0])"' "$SETTINGS")"
  [ -z "$dupes" ]
}

@test "uninstalling one installer removes only its own hooks" {
  install_all
  before="$(hook_count)"
  "$REPO_ROOT/bin/install_claude_idle_hooks.sh" --uninstall 2>/dev/null
  [ "$(hook_count)" -eq $((before - 3)) ]
  run grep -q claude_idle_recap.sh "$SETTINGS"
  [ "$status" -ne 0 ]
  jq -e '.hooks.UserPromptSubmit[].hooks[]
    | select(.command | contains("claude_context_check.sh"))' "$SETTINGS" >/dev/null
}

@test "uninstalling everything leaves no empty group or event" {
  install_all
  for i in $INSTALLERS; do
    "$REPO_ROOT/bin/$i" --uninstall 2>/dev/null
  done
  [ "$(jq '.hooks // {} | length' "$SETTINGS")" -eq 0 ]
}

@test "a second full run changes nothing" {
  install_all
  cp "$SETTINGS" "$TMP/first.json"
  install_all
  cmp -s "$SETTINGS" "$TMP/first.json"
}

@test "a group no installer owns survives, whatever its hooks hold" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"Stop":[{"matcher":"*","hooks":[]},{"matcher":"x","hooks":null}]}}' >"$SETTINGS"
  install_all
  jq -e '.hooks.Stop | any(.matcher == "*" and .hooks == [])' "$SETTINGS" >/dev/null
  jq -e '.hooks.Stop | any(.matcher == "x")' "$SETTINGS" >/dev/null
}
