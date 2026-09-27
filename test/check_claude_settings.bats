#!/usr/bin/env bats

# Tests for bin/check_claude_settings.sh: the gate between what Claude Code
# writes into the linked settings file and a commit to this public repo. The
# script checks files under its own repo, so each test runs a copy placed in a
# throwaway repo.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/claudecode"
  cp "$REPO_ROOT/bin/check_claude_settings.sh" "$TMP/repo/bin/"
  git -C "$TMP/repo" init -q
  SCRIPT="$TMP/repo/bin/check_claude_settings.sh"
  F="claudecode/settings.json"
}

teardown() {
  rm -rf "$TMP"
}

check() {
  printf '%s\n' "$1" >"$TMP/repo/$F"
  run "$SCRIPT" "$F"
}

@test "passes a file of allowed keys with portable paths" {
  check '{"theme": "auto", "statusLine": {"type": "command", "command": "exec \"$HOME/bin/x\""}}'
  [ "$status" -eq 0 ]
}

@test "stops a key that is not on the allow-list, naming it" {
  check '{"theme": "auto", "env": {"TOKEN": "x"}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *'"env"'* ]]
}

@test "stops permissions: allow rules name paths from wherever they were granted" {
  check '{"permissions": {"allow": ["Bash(ls)"]}}'
  [ "$status" -eq 1 ]
}

@test "stops an absolute home path anywhere in a value" {
  check '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash /Users/someone/x.sh"}]}]}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute home path"* ]]
}

@test "stops a Linux home path too" {
  check '{"statusLine": {"type": "command", "command": "/home/someone/bin/x"}}'
  [ "$status" -eq 1 ]
}

@test "stops a marketplace that is a local directory" {
  check '{"extraKnownMarketplaces": {"m": {"source": {"source": "directory", "path": "/tmp/m"}}}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"local directory"* ]]
}

@test "passes a GitHub marketplace" {
  check '{"extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "o/r"}}}}'
  [ "$status" -eq 0 ]
}

@test "ignores staged files outside claudecode/settings*.json" {
  printf '{"env": {}}\n' >"$TMP/repo/other.json"
  run "$SCRIPT" other.json
  [ "$status" -eq 0 ]
}

@test "with no arguments, checks every tracked settings file" {
  printf '{"env": {}}\n' >"$TMP/repo/$F"
  git -C "$TMP/repo" add "$F"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}
