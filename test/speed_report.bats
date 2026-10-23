#!/usr/bin/env bats

# speed_report.sh feeds the Speed watch log, where a later run compares against
# earlier rows. So what must hold: a missing tool reads `n/a` and a failing
# command reads `fail` (never a fast number), the median is a value that was
# actually measured, and the row keeps the issue's column order.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  TMP="$(fixture_tmpdir)"
  REPO="$TMP/repo"
  mkdir -p "$REPO/bin" "$REPO/config" "$REPO/claudecode/rules" "$REPO/.claude"
  cp "$REPO_ROOT/bin/speed_report.sh" "$REPO/bin/"
  printf 'abc\n' >"$REPO/claudecode/rules/a.md"
  printf 'defgh\n' >"$REPO/claudecode/rules/b.md"
  printf '0123456789\n' >"$REPO/AGENTS.md"
  echo '{}' >"$REPO/.claude/settings.json"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name t
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "feat: init"
  export SPEED_REPORT_HOME="$TMP/home" SPEED_REPORT_RUNS=3
  # Only what the script itself needs, so every measured tool is missing
  # unless a test puts a fake one next to these.
  BIN="$TMP/bin"
  mkdir -p "$BIN"
  for c in bash env sh mkdir ln dirname readlink awk cat grep wc tr git date perl printf sleep; do
    p=$(command -v "$c") && ln -s "$p" "$BIN/$c"
  done
}

teardown() {
  rm -rf "$TMP"
}

fake() {
  printf '#!/bin/sh\n%s\n' "$2" >"$BIN/$1"
  chmod +x "$BIN/$1"
}

report() {
  PATH="$BIN" run "$BIN/bash" "$REPO/bin/speed_report.sh" "$@"
}

@test "median: the middle value, the lower one for an even count" {
  . "$REPO_ROOT/bin/speed_report.sh"
  [ "$(printf '30\n10\n20\n' | median)" = 20 ]
  [ "$(printf '40\n10\n30\n20\n' | median)" = 20 ]
  [ "$(printf '9\n100\n' | median)" = 9 ]
}

@test "median: one failed run makes the item fail, not faster" {
  . "$REPO_ROOT/bin/speed_report.sh"
  [ "$(printf '10\nfail\n12\n' | median)" = fail ]
  [ "$(printf '' | median)" = n/a ]
}

@test "a missing tool reads n/a, never a time" {
  report zsh nvim tmux hook precommit bats
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'n/a\nn/a\nn/a\nn/a\nn/a\nn/a')" ]
}

@test "a command that fails reads fail" {
  fake zsh 'exit 1'
  report zsh
  [ "$status" -eq 0 ]
  [ "$output" = fail ]
}

@test "a command that works reads whole milliseconds, run under the measured HOME" {
  fake zsh 'echo "$HOME" >>"'"$TMP"'/homes"; sleep 0.05'
  report zsh
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -ge 50 ]
  [ "$output" -lt 1000 ]
  # One warm-up, then SPEED_REPORT_RUNS timed runs.
  [ "$(grep -c . "$TMP/homes")" -eq 4 ]
  [ "$(sort -u "$TMP/homes")" = "$TMP/home" ]
  [ -L "$TMP/home/.config" ]
}

@test "bats: the suite sees none of the toggles that quiet zsh's startup" {
  fake bats 'exit 0'
  printf '#!/bin/sh\nenv >"%s/suite.env"\n' "$TMP" >"$REPO/bin/run_tests.sh"
  chmod +x "$REPO/bin/run_tests.sh"
  report bats
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  run grep -E '^(DOTFILES_NO_|CI=)' "$TMP/suite.env"
  [ "$status" -eq 1 ]
}

@test "hook: the slowest registered hook, fed a payload on stdin" {
  command -v jq >/dev/null || skip "jq not installed"
  ln -s "$(command -v jq)" "$BIN/jq"
  cat >"$REPO/.claude/settings.json" <<'EOF'
{"hooks": {
  "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "cat >/dev/null"}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "grep -q hook_event_name && sleep 0.1"}]}]
}}
EOF
  SPEED_REPORT_RUNS=1 report hook
  [ "$status" -eq 0 ]
  [ "$output" -ge 100 ]
  [ "$output" -lt 1000 ]
}

@test "rules: bytes of claudecode/rules and AGENTS.md" {
  report rules
  [ "$status" -eq 0 ]
  [ "$output" = 21 ]
}

@test "the row keeps the issue's column order" {
  report
  [ "$status" -eq 0 ]
  sha=$(git -C "$REPO" rev-parse --short HEAD)
  date=$(TZ=Asia/Tokyo date +%Y-%m-%d)
  [ "$output" = "| $date | $sha | n/a | n/a | n/a | n/a | n/a | n/a | 21 |" ]
}

@test "rejects an unknown item" {
  report fish
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown item: fish"* ]]
}
