#!/usr/bin/env bats

# The threshold of the long-command bell in .zshrc. Whether a watched pane
# stays quiet is the e2e check's job (test/e2e/long_command_bell_test.sh).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # .zshrc is sourced whole, and anything in it that runs git must not see
  # the checkout's own config.
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SOCK="long_command_bell_$$"
  tmux -L "$SOCK" -f "$REPO_ROOT/.tmux.conf" new-session -d -s BELL
  TMUX_VALUE="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),0,0"
}

teardown() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
}

# A command that ran <elapsed> seconds ends, under threshold <value>, in a
# pane no client shows; the output is what the prompt would print above it.
finish_command() {
  run zsh -f -c "
    export ZDOTDIR='$REPO_ROOT' DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    export TMUX='$TMUX_VALUE' TMUX_PANE=%999 LONG_COMMAND_BELL_SECONDS='$2'
    _long_command_started=\$(( SECONDS - $1 ))
    _long_command_bell
  "
}

@test "a command over the threshold rings, one under it does not" {
  finish_command 40 30
  [ "$status" -eq 0 ]
  [ "$output" = $'\a' ]
  finish_command 10 30
  [ "$output" = "" ]
}

@test "a threshold that is not a whole number of seconds falls back to 30" {
  finish_command 40 30s
  [ "$status" -eq 0 ]
  [ "$output" = $'\a' ]
  finish_command 10 30s
  [ "$output" = "" ]
  finish_command 10 SECONDS
  [ "$output" = "" ]
}
