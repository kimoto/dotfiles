#!/usr/bin/env bats

# Tests for bin/check_claude_settings.sh: the gate between what Claude Code
# writes into the linked settings file and a commit to this public repo. The
# script checks files under its own repo, so each test runs a copy placed in a
# throwaway repo.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
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
  check '{"theme": "auto", "apiKeyHelper": "x"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *'"apiKeyHelper"'* ]]
}

@test "stops an env variable that is not one of Claude Code's own" {
  check '{"env": {"TOKEN": "x"}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *'"TOKEN"'* ]]
}

@test "stops a CLAUDE_CODE_ variable that is not on the allow-list, such as a token" {
  check '{"env": {"CLAUDE_CODE_OAUTH_TOKEN": "x"}}'
  [ "$status" -eq 1 ]
}

@test "stops a URL that carries a credential" {
  check '{"extraKnownMarketplaces": {"m": {"source": {"source": "git", "url": "https://u:secret@example.com/m.git"}}}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential in a URL"* ]]
}

@test "passes Claude Code's own env variables" {
  check '{"env": {"CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS": "400000"}}'
  [ "$status" -eq 0 ]
}

@test "passes permissions that only deny" {
  check '{"permissions": {"deny": ["Bash(security dump-keychain:*)"]}}'
  [ "$status" -eq 0 ]
}

@test "passes permissions that ask: an ask rule only adds a prompt" {
  check '{"permissions": {"ask": ["Edit(~/.claude/rules/**)"]}}'
  [ "$status" -eq 0 ]
}

@test "stops any other permissions key, such as defaultMode" {
  check '{"permissions": {"defaultMode": "bypassPermissions"}}'
  [ "$status" -eq 1 ]
}

@test "passes model and attribution" {
  check '{"model": "opus", "attribution": {"pr": ""}}'
  [ "$status" -eq 0 ]
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
  printf '{"apiKeyHelper": "x"}\n' >"$TMP/repo/$F"
  git -C "$TMP/repo" add "$F"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "stops env or permissions that are not objects instead of crashing" {
  check '{"env": "x"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *'env is not an object'* ]]
  check '{"permissions": []}'
  [ "$status" -eq 1 ]
  [[ "$output" == *'permissions is not an object'* ]]
  check '[1]'
  [ "$status" -eq 1 ]
}

@test "stops a root or Windows home path" {
  check '{"statusLine": {"command": "/root/bin/x"}}'
  [ "$status" -eq 1 ]
  check '{"statusLine": {"command": "C:\\Users\\someone\\bin\\x"}}'
  [ "$status" -eq 1 ]
}

@test "checks a staged file even when the working copy is gone" {
  printf '%s\n' '{"apiKeyHelper": "x"}' >"$TMP/repo/$F"
  git -C "$TMP/repo" add "$F"
  rm "$TMP/repo/$F"
  run "$SCRIPT" "$F"
  [ "$status" -eq 1 ]
}

@test "checks an intent-to-add file by its working copy" {
  printf '%s\n' '{"apiKeyHelper": "x"}' >"$TMP/repo/$F"
  git -C "$TMP/repo" add -N "$F"
  run "$SCRIPT" "$F"
  [ "$status" -eq 1 ]
}

@test "lets a URL with /root/ in its path through, and stops a lowercase Windows home" {
  check '{"extraKnownMarketplaces": {"m": {"source": {"source": "git",
    "url": "https://git.example.com/root/plugins.git"}}}}'
  [ "$status" -eq 0 ]
  check '{"statusLine": {"command": "c:\\users\\someone\\bin\\x"}}'
  [ "$status" -eq 1 ]
}

@test "checks what is staged, not the working tree" {
  printf '%s\n' '{"apiKeyHelper": "x"}' >"$TMP/repo/$F"
  git -C "$TMP/repo" add "$F"
  printf '%s\n' '{"theme": "auto"}' >"$TMP/repo/$F"
  run "$SCRIPT" "$F"
  [ "$status" -eq 1 ]
}

# The file mkworld links in is rewritten by its installers on every run, so a
# committed copy they would change shows up as a dirty tree after bootstrap.
@test "claudecode/settings.json is what mkworld's installers leave" {
  mkdir -p "$TMP/home/.claude"
  cp "$REPO_ROOT/claudecode/settings.json" "$TMP/home/.claude/settings.json"
  # Without jq every installer skips, and the comparison would prove nothing.
  command -v jq >/dev/null || skip "jq not installed"
  # The installers and their order come from mkworld.sh itself, so one added
  # there is covered here too.
  installers="$(grep -o 'bin/install_claude_[a-z_]*\.sh' "$REPO_ROOT/bin/mkworld.sh")"
  [ -n "$installers" ]
  for i in $installers; do
    HOME="$TMP/home" CLAUDE_HOOK_BIN= "$REPO_ROOT/$i" 2>/dev/null
  done
  cmp "$REPO_ROOT/claudecode/settings.json" "$TMP/home/.claude/settings.json"
}
