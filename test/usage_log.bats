#!/usr/bin/env bats

# The usage log: the .zshrc preexec hook keeps only command names, and
# usage_counts.sh counts them over a window of days. What matters most is that
# no argument ever reaches the log, since everything typed passes through it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # .zshrc is sourced whole, and anything in it that runs git must not see
  # the checkout's own config.
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  WORK="$(mktemp -d)"
  export XDG_STATE_HOME="$WORK/state"
  LOG_DIR="$XDG_STATE_HOME/dotfiles/usage"
}

teardown() {
  rm -rf "$WORK"
}

# Runs the hook on each argument as if it were a typed command line.
type_commands() {
  local lines="" line
  for line in "$@"; do
    printf -v line "%q" "$line"
    lines+="_usage_log_record $line"$'\n'
  done
  run zsh -f -c "
    export ZDOTDIR='$REPO_ROOT' DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    $lines
  "
}

logged() {
  cat "$LOG_DIR"/*.log
}

@test "the hook logs the name in each command position and no argument" {
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\n' >"$WORK/bin/x.sh"
  chmod +x "$WORK/bin/x.sh"
  type_commands \
    "FOO=secret sudo -E git commit -m \"token abc\" | grep needle && $WORK/bin/x.sh /private/path; echo hi"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ "$(logged)" = "$(printf 'git\ngrep\nx.sh\necho')" ]
  ! grep -rqE 'secret|token|needle|private|hi' "$LOG_DIR"
}

@test "a word zsh would not run is dropped, so a mistyped password never lands" {
  type_commands 'hunter2pass' 'xK9fQ2mZ7pL4wR8tY1vB6nC3' '"$EDITOR" notes.txt' \
    "'quoted cmd' arg" '$(curl evil)' './missing.sh' 'ls'
  [ "$status" -eq 0 ]
  [ "$(logged)" = "ls" ]
}

@test "the command inside a loop is logged, not its keywords or its list" {
  type_commands 'for pkg in git cat; do grep x; done' 'if true; then sort; fi' '[[ -n ls ]] && wc'
  [ "$status" -eq 0 ]
  [ "$(logged)" = "$(printf 'grep\ntrue\nsort\nwc')" ]
}

@test "nothing after a word that is not a command is logged" {
  type_commands 'nosuchcmd -u git' 'mytypo cat file' 'sudo mytypo cat secretfile'
  [ "$status" -eq 0 ]
  [ ! -e "$LOG_DIR" ]
}

@test "redirections before the command and declaration builtins are logged right" {
  type_commands '<input.txt grep foo' '2>/dev/null sort' 'export PATH=/x' 'typeset -f ls'
  [ "$status" -eq 0 ]
  [ "$(logged)" = "$(printf 'grep\nsort\nexport\ntypeset')" ]
}

@test "a command given as ~/path is found" {
  export HOME="$WORK"
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\n' >"$WORK/bin/tool.sh"
  chmod +x "$WORK/bin/tool.sh"
  type_commands '~/bin/tool.sh arg'
  [ "$status" -eq 0 ]
  [ "$(logged)" = "tool.sh" ]
}

@test "a heredoc body is never read" {
  type_commands $'cat <<EOF >conf\ns3cr3tPassw0rd\nls\nEOF'
  [ "$status" -eq 0 ]
  [ "$(logged)" = "cat" ]
}

@test "the first command of a day creates its file and the directory is private" {
  # The clock is read on both sides, as the hook may run across midnight.
  local before after
  before="$(date +%Y-%m-%d).log"
  type_commands 'ls' 'ls'
  after="$(date +%Y-%m-%d).log"
  [ "$status" -eq 0 ]
  [[ "$(ls "$LOG_DIR")" == "$before" || "$(ls "$LOG_DIR")" == "$after" ]]
  [ "$(logged)" = "$(printf 'ls\nls')" ]
  [ "$(stat -c %a "$LOG_DIR" 2>/dev/null || stat -f %Lp "$LOG_DIR")" = 700 ]
}

@test "DOTFILES_NO_USAGE_LOG turns the log off" {
  export DOTFILES_NO_USAGE_LOG=1
  type_commands 'ls'
  [ "$status" -eq 0 ]
  [ ! -e "$LOG_DIR" ]
}

counts() {
  USAGE_COUNTS_TODAY=2026-11-28 run "$REPO_ROOT/bin/usage_counts.sh" "$@"
}

write_day() {
  mkdir -p "$LOG_DIR"
  printf '%s\n' "${@:2}" >"$LOG_DIR/$1.log"
}

@test "counts cover the last 7 days by default, most used first" {
  write_day 2026-11-21 old old old
  write_day 2026-11-22 git ls
  write_day 2026-11-28 git rg git
  counts
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# 2026-11-22 to 2026-11-28, 2 days logged" ]
  [ "${lines[1]}" = "$(printf '3\tgit')" ]
  [ "${lines[2]}" = "$(printf '1\tls')" ]
  [ "${lines[3]}" = "$(printf '1\trg')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "--days and --all widen the window" {
  write_day 2026-11-01 old
  write_day 2026-11-28 git
  counts --days 1
  [ "${#lines[@]}" -eq 2 ]
  counts --days 28
  [ "${lines[0]}" = "# 2026-11-01 to 2026-11-28, 2 days logged" ]
  counts --all
  [[ "$output" == *"$(printf '1\told')"* ]]
}

@test "bad arguments and a missing log fail with a message" {
  counts --days 0
  [ "$status" -eq 2 ]
  counts --days x
  [ "$status" -eq 2 ]
  counts --bogus
  [ "$status" -eq 2 ]
  counts --all --days 3
  [ "$status" -eq 2 ]
  counts --days 3 --all
  [ "$status" -eq 2 ]
  counts
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usage log yet"* ]]
}

@test "an empty window says so" {
  write_day 2026-10-01 old
  counts
  [ "$status" -eq 0 ]
  [ "$output" = "# no days logged since 2026-11-22" ]
}
