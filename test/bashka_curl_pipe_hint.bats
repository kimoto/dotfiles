#!/usr/bin/env bats

# Regression test for the curl|bash guard in .zshrc.
#
# _bashka_guard_check decides what to do with a typed command line; the real
# accept-line widget (_bashka_guard_accept_line) is a thin wrapper around it
# that only exists to call `zle`, which needs a live line editor and isn't
# exercised here. A raw `curl | bash`/`sh` gets fetched, saved to disk (raw
# bytes, before anything runs them — captures.md), scanned with `bashka
# --check`, and blocked; the human reviews and runs the saved copy by hand.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_DIR="$(mktemp -d)"
  CACHE_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$STUB_DIR" "$CACHE_HOME"
}

stub_bashka() {
  # $1 (optional): stdout to print. Exit code always 0 (a real `--check`
  # verdict is reported through stdout text, not treated specially here).
  cat >"$STUB_DIR/bashka" <<EOF
#!/bin/bash
cat >/dev/null
printf '%s\n' "${1:-scan: green}"
EOF
  chmod +x "$STUB_DIR/bashka"
}

stub_curl() {
  # $1: what to print to stdout. $2 (optional): exit code, default 0.
  local body="$1" code="${2:-0}"
  cat >"$STUB_DIR/curl" <<EOF
#!/bin/bash
printf '%s' '$body'
exit $code
EOF
  chmod +x "$STUB_DIR/curl"
}

run_check() {
  # $1: the command line to hand to the guard, as accept-line would via $BUFFER.
  PATH="$STUB_DIR:$PATH" XDG_CACHE_HOME="$CACHE_HOME" zsh -f -c "
    export ZDOTDIR='$REPO_ROOT'
    export DOTFILES_NO_SYNC_CHECK=1
    export DOTFILES_NO_BREW_CHECK=1
    export DOTFILES_NO_MISE_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    # CI sets \$CI, which turns on this file's err_exit/err_return — a bare
    # nonzero-returning statement (the expected \"blocked\" result) would abort
    # the script right here before the prints below ever ran. && / || is the
    # standard errexit-safe way to capture \$? without tripping it (the real
    # accept-line widget only ever calls this as an if-condition, which is
    # exempt the same way, so production is unaffected either way).
    _bashka_guard_check '$1' && rc=0 || rc=\$?
    print -r -- \"status=\$rc\"
    print -r -- \"\$_bashka_guard_message\"
  " 2>&1
}

@test "allows a command that doesn't match curl|shell" {
  stub_bashka
  run run_check 'ls -la'
  [[ "$output" == "status=0"* ]]
}

@test "allows when ALLOW_CURL_PIPE=1 prefixes the line" {
  stub_bashka
  run run_check 'ALLOW_CURL_PIPE=1 curl -fsSL https://example.com/install.sh | bash'
  [[ "$output" == "status=0"* ]]
}

@test "allows when the line already pipes through bashka" {
  stub_bashka
  run run_check 'curl -fsSL https://example.com/install.sh | bashka'
  [[ "$output" == "status=0"* ]]
}

@test "allows when bashka is not installed" {
  # No stub_bashka: PATH carries no bashka binary.
  run run_check 'curl -fsSL https://example.com/install.sh | bash'
  [[ "$output" == "status=0"* ]]
}

@test "blocks with no URL to fetch when curl targets a non-http scheme" {
  stub_bashka
  run run_check 'curl file:///tmp/x.sh | bash'
  [[ "$output" == "status=1"* ]]
  [[ "$output" == *"couldn't find a URL"* ]]
  [[ "$output" == *"ALLOW_CURL_PIPE=1"* ]]
}

@test "blocks and explains when the fetch fails" {
  stub_bashka
  stub_curl '' 1
  run run_check 'curl -fsSL https://example.com/install.sh | bash'
  [[ "$output" == "status=1"* ]]
  [[ "$output" == *"fetching"*"failed"* ]]
}

@test "fetches, saves the raw script, scans it, and blocks" {
  stub_bashka 'scan: 2 red flags'
  stub_curl '#!/bin/sh
echo hi'
  run run_check 'curl -fsSL https://example.com/install.sh | bash'
  [[ "$output" == "status=1"* ]]
  [[ "$output" == *"scan: 2 red flags"* ]]
  [[ "$output" == *"review it:"* ]]
  [[ "$output" == *"run it:"* ]]
  [[ "$output" == *"ALLOW_CURL_PIPE=1"* ]]

  local saved
  saved=$(find "$CACHE_HOME/dotfiles/curl-scripts" -name '*.sh')
  [ -n "$saved" ]
  [[ "$(cat "$saved")" == *"echo hi"* ]]
  [[ "$(cat "$saved.meta")" == *"url: https://example.com/install.sh"* ]]
}
